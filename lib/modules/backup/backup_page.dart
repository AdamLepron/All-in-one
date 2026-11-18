import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../notes/notes_store.dart';
import '../recorder/recorder_controller.dart';
import '../scanner/scan_store.dart';
import '../tasks/organizer_store.dart';
import 'backup_service.dart';

/// Where backups are saved on the phone.
const backupsDirectory = '$storageRoot/Documents/All-in-One/Sauvegardes';

/// Picks a backup file and returns its path, or null if cancelled.
typedef BackupPicker = Future<String?> Function();

Future<String?> pickBackupFile() async {
  final file = await FilePicker.pickFile();
  if (file == null) return null;
  final path = file.path;
  if (path != null) return path;
  // A content:// address: copy it to a real file, streaming.
  final dir = Directory('${(await getTemporaryDirectory()).path}/restore_pick');
  await dir.create(recursive: true);
  final copy = File(await uniquePath(dir.path, safeName(file.name)));
  final sink = copy.openWrite();
  await sink.addStream(file.xFile.openRead());
  await sink.close();
  return copy.path;
}

String safeName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

class BackupPage extends StatefulWidget {
  const BackupPage({
    super.key,
    this.directory = backupsDirectory,
    this.pickFile = pickBackupFile,
  });

  final String directory;
  final BackupPicker pickFile;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _includeFiles = true;
  bool _busy = false;
  List<File> _backups = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final dir = Directory(widget.directory);
    final list = <File>[];
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is File &&
            e.path.endsWith('.zip') &&
            p.basename(e.path).startsWith('All-in-One-sauvegarde')) {
          list.add(e);
        }
      }
    }
    list.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (mounted) setState(() => _backups = list);
  }

  Future<BackupService> _service() async {
    final scans = context.read<ScanStore>();
    final recorder = context.read<RecorderController>();
    final scansDir = await scans.rootDirectory;
    final recordingsDir = await recorder.directory;
    if (!mounted) throw StateError('closed');
    return BackupService(
      notes: context.read<NotesStore>(),
      organizer: context.read<OrganizerStore>(),
      settings: context.read<AppSettings>(),
      scansDir: scansDir,
      recordingsDir: recordingsDir,
    );
  }

  Future<void> _create() async {
    if (widget.directory == backupsDirectory &&
        !await ensureFullFileAccess(context)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final service = await _service();
      final path = await service.create(
        outputDir: widget.directory,
        includeFiles: _includeFiles,
      );
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Sauvegarde créée : ${p.basename(path)}'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Partager',
              onPressed: () =>
                  SharePlus.instance.share(ShareParams(files: [XFile(path)])),
            ),
          ),
        );
    } on Object {
      if (mounted) showMessage(context, 'La sauvegarde a échoué');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFrom(String path) async {
    final BackupInfo info;
    try {
      info = await (await _service()).inspect(path);
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message);
      return;
    } on Object {
      if (mounted) showMessage(context, 'Ce fichier ne peut pas être lu');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Créée le ${fullDate(info.created)}'),
            const SizedBox(height: 8),
            Text(
              '${info.notes} note${info.notes > 1 ? 's' : ''}, '
              '${info.tasks} tâche${info.tasks > 1 ? 's' : ''}, '
              '${info.events} événement${info.events > 1 ? 's' : ''}'
              '${info.files > 0 ? ', ${info.files} fichier${info.files > 1 ? 's' : ''} (scans, enregistrements)' : ''}',
            ),
            const SizedBox(height: 12),
            const Text(
              'Les notes, tâches, événements et réglages actuels seront remplacés par ceux de la sauvegarde.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Remplacer et restaurer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final service = await _service();
      await service.restore(path);
      if (!mounted) return;
      await context.read<ScanStore>().load();
      if (!mounted) return;
      await context.read<RecorderController>().load();
      if (mounted) {
        showMessage(
          context,
          'Restauration terminée. Certains réglages s\'appliqueront au prochain lancement.',
        );
      }
    } on Object {
      if (mounted) {
        showMessage(
          context,
          'La restauration a échoué : rien n\'a été modifié',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndRestore() async {
    final path = await widget.pickFile();
    if (path != null) await _restoreFrom(path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sauvegarde et restauration')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              'Vos notes, tâches, événements et réglages ne sont gardés que sur ce téléphone. '
              'Une sauvegarde les rassemble dans un fichier que vous pouvez ranger où vous voulez.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          SwitchListTile(
            title: const Text('Inclure les scans et enregistrements'),
            subtitle: const Text('Le fichier est plus volumineux'),
            value: _includeFiles,
            onChanged: _busy ? null : (v) => setState(() => _includeFiles = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Créer une sauvegarde'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickAndRestore,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restaurer…'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
            child: Text(
              'Sur ce téléphone',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'Aucune sauvegarde dans Documents / All-in-One / Sauvegardes.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          for (final f in _backups)
            ListTile(
              leading: const Icon(Icons.folder_zip_outlined),
              title: Text(
                p.basename(f.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${formatBytes(f.lengthSync())} · ${relativeDate(f.statSync().modified)}',
              ),
              onTap: _busy ? null : () => _restoreFrom(f.path),
              trailing: PopupMenuButton<VoidCallback>(
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: () => SharePlus.instance.share(
                      ShareParams(files: [XFile(f.path)]),
                    ),
                    child: const Text('Partager'),
                  ),
                  PopupMenuItem(
                    value: () async {
                      await f.delete();
                      await _refresh();
                    },
                    child: const Text('Supprimer'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
