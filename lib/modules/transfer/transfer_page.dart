import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'transfer_server.dart';

/// Where files received from other devices are saved.
const receivedDir = '$storageRoot/Download/All-in-One';

/// Entry of the module: send files, or receive them.
class TransferPage extends StatelessWidget {
  const TransferPage({super.key, this.receiveDirectory = receivedDir});
  final String receiveDirectory;

  Future<void> _send(BuildContext context) async {
    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles();
    } on Object {
      if (context.mounted) {
        showMessage(context, 'Impossible de choisir des fichiers');
      }
      return;
    }
    if (picked.isEmpty || !context.mounted) return;
    final files = <SharedFile>[];
    try {
      final temp = Directory(
        '${(await getTemporaryDirectory()).path}/transfer',
      );
      for (final f in picked) {
        final path = f.path;
        if (path != null) {
          files.add(SharedFile(path, File(path).lengthSync()));
        } else {
          // A content:// address: copy it to a real file, streaming.
          await temp.create(recursive: true);
          final copy = File(await uniquePath(temp.path, safeFileName(f.name)));
          final sink = copy.openWrite();
          await sink.addStream(f.xFile.openRead());
          await sink.close();
          files.add(SharedFile(copy.path, copy.lengthSync()));
        }
      }
    } on Object {
      if (context.mounted) {
        showMessage(context, 'Impossible de lire ces fichiers');
      }
      return;
    }
    if (files.isEmpty || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransferSessionPage(files: files),
      ),
    );
  }

  Future<void> _receive(BuildContext context) async {
    if (!await ensureFullFileAccess(context) || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransferSessionPage(receiveDir: receiveDirectory),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget card(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Transfert local')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card(
            Icons.upload_rounded,
            'Envoyer des fichiers',
            'Choisissez des fichiers : l\'autre appareil les télécharge avec un QR code.',
            () => _send(context),
          ),
          const SizedBox(height: 12),
          card(
            Icons.download_rounded,
            'Recevoir des fichiers',
            "L'autre appareil envoie ses fichiers depuis son navigateur, vers Téléchargements.",
            () => _receive(context),
          ),
          const SizedBox(height: 24),
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Les deux appareils doivent être sur le même réseau Wi-Fi, ou l\'un connecté au partage de connexion de l\'autre. '
                'Aucun compte, aucune application à installer sur l\'autre appareil (téléphone, tablette ou ordinateur) : un navigateur suffit. '
                'Rien ne passe par Internet.',
                style: TextStyle(
                  color: scheme.onSecondaryContainer,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A running transfer: the QR code, the address and the activity.
class TransferSessionPage extends StatefulWidget {
  const TransferSessionPage({
    super.key,
    this.files = const [],
    this.receiveDir,
  });
  final List<SharedFile> files;
  final String? receiveDir;

  @override
  State<TransferSessionPage> createState() => _TransferSessionPageState();
}

class _TransferSessionPageState extends State<TransferSessionPage> {
  late final TransferServer _server = TransferServer(
    files: widget.files,
    receiveDir: widget.receiveDir,
    approve: widget.receiveDir == null ? null : _askApproval,
  );

  /// Another device wants to send a file: the owner decides.
  Future<UploadDecision> _askApproval(String from, String name) async {
    if (!mounted) return UploadDecision.refuse;
    final result = await showDialog<UploadDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        title: const Text('Accepter ce fichier ?'),
        content: Text(
          "L'appareil $from veut envoyer « $name » vers ce téléphone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, UploadDecision.refuse),
            child: const Text('Refuser'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, UploadDecision.acceptAll),
            child: const Text('Tout accepter'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, UploadDecision.accept),
            child: const Text('Accepter'),
          ),
        ],
      ),
    );
    return result ?? UploadDecision.refuse;
  }

  List<String>? _addresses;
  String? _error;
  StreamSubscription<void>? _subscription;
  int _selected = 0;

  bool get _receiving => widget.receiveDir != null;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final addresses = await TransferServer.localAddresses();
      await _server.start();
      _subscription = _server.changes.listen((_) {
        if (mounted) setState(() {});
      });
      unawaited(MediaChannel.keepScreenOn(true));
      if (mounted) setState(() => _addresses = addresses);
    } on Object {
      if (mounted) setState(() => _error = 'Impossible de démarrer le partage');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _server.stop();
    MediaChannel.keepScreenOn(false);
    final received = _server.events.where((e) => e.upload && e.done);
    if (received.isNotEmpty && widget.receiveDir != null) {
      MediaChannel.scan([
        for (final e in received) p.join(widget.receiveDir!, e.name),
      ]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final addresses = _addresses;
    final url = addresses == null || addresses.isEmpty
        ? null
        : _server.urlFor(addresses[_selected.clamp(0, addresses.length - 1)]);

    return Scaffold(
      appBar: AppBar(title: Text(_receiving ? 'Recevoir' : 'Envoyer')),
      body: _error != null
          ? Center(child: Text(_error!))
          : addresses == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (url == null)
                  Card(
                    color: scheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Aucun réseau détecté. Connectez-vous à un Wi-Fi ou activez le partage de connexion, puis revenez ici.',
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  )
                else ...[
                  Text(
                    _receiving
                        ? "Sur l'autre appareil, scannez ce code ou ouvrez l'adresse dans un navigateur, puis choisissez les fichiers à envoyer."
                        : "Sur l'autre appareil, scannez ce code ou ouvrez l'adresse dans un navigateur pour télécharger.",
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(14),
                      child: QrImageView(data: url, size: 220),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SelectableText(
                      url,
                      textAlign: TextAlign.center,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          showMessage(context, 'Adresse copiée');
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copier'),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            SharePlus.instance.share(ShareParams(text: url)),
                        icon: const Icon(Icons.share_outlined, size: 18),
                        label: const Text('Partager'),
                      ),
                    ],
                  ),
                  if (addresses.length > 1)
                    Center(
                      child: Wrap(
                        spacing: 8,
                        children: [
                          for (var i = 0; i < addresses.length; i++)
                            ChoiceChip(
                              showCheckmark: false,
                              label: Text(addresses[i]),
                              selected: i == _selected,
                              onSelected: (_) => setState(() => _selected = i),
                            ),
                        ],
                      ),
                    ),
                ],
                if (!_receiving) ...[
                  const SizedBox(height: 20),
                  Text(
                    '${widget.files.length} fichier${widget.files.length > 1 ? 's' : ''} proposé${widget.files.length > 1 ? 's' : ''}',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final f in widget.files)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(formatBytes(f.size)),
                    ),
                ],
                const SizedBox(height: 16),
                Text(
                  'Activité',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (_server.events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'En attente de l\'autre appareil…',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                for (final e in _server.events)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      e.done
                          ? Icons.check_circle_rounded
                          : e.upload
                          ? Icons.south_rounded
                          : Icons.north_rounded,
                      color: e.done ? const Color(0xFF30A46C) : scheme.primary,
                    ),
                    title: Text(
                      e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: e.done || e.total == null
                        ? Text(
                            e.done
                                ? (e.upload
                                      ? 'Reçu · ${formatBytes(e.bytes)}'
                                      : 'Envoyé · ${formatBytes(e.bytes)}')
                                : '${formatBytes(e.bytes)} reçus…',
                          )
                        : LinearProgressIndicator(value: e.bytes / e.total!),
                    onTap: e.done && e.upload && widget.receiveDir != null
                        ? () =>
                              OpenFilex.open(p.join(widget.receiveDir!, e.name))
                        : null,
                  ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Arrêter le partage'),
                ),
                if (_receiving)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Les fichiers reçus sont enregistrés dans Téléchargements / All-in-One.',
                      textAlign: TextAlign.center,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Opens a sending session for [paths] (files only), from a file or gallery
/// menu. Folders are skipped.
Future<void> sendByWifi(BuildContext context, List<String> paths) async {
  final files = <SharedFile>[];
  for (final path in paths) {
    final f = File(path);
    if (await f.exists()) files.add(SharedFile(path, await f.length()));
  }
  if (!context.mounted) return;
  if (files.isEmpty) {
    showMessage(context, 'Choisissez des fichiers (pas des dossiers)');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TransferSessionPage(files: files)),
  );
}
