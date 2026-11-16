import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../core/platform.dart';
import '../../core/util.dart';
import 'file_ops.dart';
import 'files_ui.dart';
import 'folder_page.dart';

const _shortcuts = <(String, String, FileKind)>[
  ('Téléchargements', 'Download', FileKind.archive),
  ('Images', 'Pictures', FileKind.image),
  ('Appareil photo', 'DCIM', FileKind.image),
  ('Vidéos', 'Movies', FileKind.video),
  ('Musique', 'Music', FileKind.audio),
  ('Documents', 'Documents', FileKind.document),
];

/// Home of the file manager: storage gauge, shortcuts and recycle bin.
class FilesPage extends StatefulWidget {
  const FilesPage({super.key});

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> with WidgetsBindingObserver {
  bool? _granted;
  ({int total, int free})? _storage;
  int _trashCount = 0;
  final _trash = Trash.device();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Full file access is granted on a system settings screen.
    if (state == AppLifecycleState.resumed && _granted != true) _check();
  }

  Future<bool> _hasAccess() async {
    try {
      return await Permission.manageExternalStorage.isGranted ||
          await Permission.storage.isGranted;
    } on MissingPluginException {
      return true; // not on a device (tests)
    }
  }

  Future<void> _check() async {
    final granted = await _hasAccess();
    if (!mounted) return;
    setState(() => _granted = granted);
    if (granted) _refresh();
  }

  Future<void> _request() async {
    if (!await Permission.manageExternalStorage.request().isGranted) {
      await Permission.storage.request();
    }
    await _check();
    if (mounted && _granted == false) {
      showMessage(
        context,
        "Accès refusé",
        action: SnackBarAction(label: 'Réglages', onPressed: openAppSettings),
      );
    }
  }

  Future<void> _refresh() async {
    final storage = await MediaChannel.storage();
    await _trash.purgeExpired();
    final count = (await _trash.items()).length;
    if (mounted) {
      setState(() {
        _storage = storage;
        _trashCount = count;
      });
    }
  }

  Future<void> _browse(String path) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FolderPage(path: path)));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fichiers')),
      body: switch (_granted) {
        null => const Center(child: CircularProgressIndicator()),
        false => _PermissionRequest(onRequest: _request),
        true => _home(context),
      },
    );
  }

  Widget _home(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final storage = _storage;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _browse(storageRoot),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.smartphone_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Stockage interne',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  if (storage != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 10,
                        value: (storage.total - storage.free) / storage.total,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${formatBytes(storage.total - storage.free)} utilisés sur ${formatBytes(storage.total)} · ${formatBytes(storage.free)} libres',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
          child: Text(
            'Accès rapide',
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: [
            for (final (label, folder, kind) in _shortcuts)
              Material(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _browse(p.join(storageRoot, folder)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      KindIcon(kind),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Corbeille'),
            subtitle: Text(
              _trashCount == 0
                  ? 'Vide'
                  : '$_trashCount élément${_trashCount > 1 ? 's' : ''} · suppression après 30 jours',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TrashPage(trash: _trash)),
              );
              if (mounted) _refresh();
            },
          ),
        ),
      ],
    );
  }
}

class _PermissionRequest extends StatelessWidget {
  const _PermissionRequest({required this.onRequest});
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KindIcon(FileKind.folder, size: 88),
            const SizedBox(height: 24),
            Text(
              'Accès à vos fichiers',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              "Pour parcourir, copier et organiser vos dossiers, l'application a besoin d'accéder au stockage du téléphone. Rien ne quitte votre appareil.",
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onRequest,
              child: const Text("Autoriser l'accès"),
            ),
          ],
        ),
      ),
    );
  }
}

class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.trash});
  final Trash trash;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.trash.items();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _confirmEmpty() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vider la corbeille ?'),
        content: const Text('Ces éléments seront supprimés définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await widget.trash.empty();
      await _load();
    }
  }

  void _actions(TrashItem item) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restaurer'),
              subtitle: Text(p.dirname(item.original)),
              onTap: () async {
                Navigator.pop(sheet);
                await widget.trash.restore(item);
                await _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Supprimer définitivement'),
              onTap: () async {
                Navigator.pop(sheet);
                await widget.trash.remove(item);
                await _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Corbeille'),
        actions: [
          if (items != null && items.isNotEmpty)
            TextButton(onPressed: _confirmEmpty, child: const Text('Vider')),
        ],
      ),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('La corbeille est vide'))
          : ListView(
              children: [
                for (final item in items)
                  ListTile(
                    leading: KindIcon(kindOfPath(item.original)),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Supprimé ${relativeDate(item.deletedAt).toLowerCase()}',
                    ),
                    onTap: () => _actions(item),
                  ),
              ],
            ),
    );
  }
}
