import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/platform.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_page.dart' show TrashPage;
import '../files/files_ui.dart';
import 'cleaner_scan.dart';

const _icons = <CleanCategory, IconData>{
  CleanCategory.duplicates: Icons.file_copy_outlined,
  CleanCategory.large: Icons.sd_storage_outlined,
  CleanCategory.oldDownloads: Icons.download_outlined,
  CleanCategory.screenshots: Icons.screenshot_outlined,
  CleanCategory.apks: Icons.android_rounded,
  CleanCategory.junk: Icons.auto_delete_outlined,
};

/// Storage overview with suggestions of what to remove.
class CleanerPage extends StatefulWidget {
  const CleanerPage({super.key, this.root = storageRoot, this.trash});
  final String root;
  final Trash? trash;

  @override
  State<CleanerPage> createState() => _CleanerPageState();
}

class _CleanerPageState extends State<CleanerPage> {
  late final Trash _trash = widget.trash ?? Trash.device();
  CleanReport? _report;
  bool _denied = false;
  int _examined = 0;
  ({int total, int free})? _storage;
  int _trashSize = 0;
  int _trashCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
  }

  Future<void> _analyze() async {
    if (widget.root == storageRoot && !await ensureFullFileAccess(context)) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    if (mounted) {
      setState(() {
        _denied = false;
        _report = null;
        _examined = 0;
      });
    }
    final report = await analyzeStorage(
      widget.root,
      onProgress: (n) {
        if (mounted) setState(() => _examined = n);
      },
    );
    final storage = await MediaChannel.storage();
    await _measureTrash();
    if (mounted) {
      setState(() {
        _report = report;
        _storage = storage;
      });
    }
  }

  Future<void> _measureTrash() async {
    final items = await _trash.items();
    var size = 0;
    for (final item in items) {
      try {
        size += await sizeOf(_trash.pathOf(item));
      } on Exception {
        continue;
      }
    }
    if (mounted) {
      setState(() {
        _trashCount = items.length;
        _trashSize = size;
      });
    }
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Vider la corbeille ?'),
        content: Text(
          '${formatBytes(_trashSize)} seront libérés. Cette action est définitive.',
        ),
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
    if (ok != true) return;
    final freed = _trashSize;
    await _trash.empty();
    await _measureTrash();
    final storage = await MediaChannel.storage();
    if (mounted) {
      setState(() => _storage = storage);
      showMessage(context, '${formatBytes(freed)} libérés');
    }
  }

  Future<void> _review(CleanCategory category) async {
    final cleaned = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _ReviewPage(
          category: category,
          items: _report!.items[category]!,
          trash: _trash,
        ),
      ),
    );
    if (cleaned == true) await _analyze();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final report = _report;
    final storage = _storage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nettoyeur'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: 'Analyser à nouveau',
              icon: const Icon(Icons.refresh),
              onPressed: _analyze,
            ),
        ],
      ),
      body: _denied
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cleaning_services_outlined,
                      size: 72,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "L'accès aux fichiers est nécessaire pour analyser le stockage.",
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _analyze,
                      child: const Text("Autoriser l'accès"),
                    ),
                  ],
                ),
              ),
            )
          : report == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  Text('Analyse du stockage…', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '$_examined fichiers examinés',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.totalGain == 0
                              ? 'Rien à nettoyer'
                              : '${formatBytes(report.totalGain)} à libérer',
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (storage != null) ...[
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              minHeight: 10,
                              value:
                                  (storage.total - storage.free) /
                                  storage.total,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${formatBytes(storage.total - storage.free)} utilisés sur ${formatBytes(storage.total)} · ${formatBytes(storage.free)} libres',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Rien n\'est supprimé sans votre accord : chaque catégorie se vérifie avant nettoyage.',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final category in CleanCategory.values)
                  if (report.items[category]!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor: scheme.secondaryContainer,
                            child: Icon(
                              _icons[category],
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          title: Text(
                            category.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${report.items[category]!.length} élément${report.items[category]!.length > 1 ? 's' : ''} · ${category.description}',
                          ),
                          trailing: Text(
                            formatBytes(
                              category == CleanCategory.large
                                  ? report.items[category]!.fold(
                                      0,
                                      (s, i) => s + i.size,
                                    )
                                  : report.gain(category),
                            ),
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.primary,
                            ),
                          ),
                          onTap: () => _review(category),
                        ),
                      ),
                    ),
                if (_trashCount > 0)
                  Card(
                    color: scheme.tertiaryContainer,
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                      leading: Icon(
                        Icons.delete_outline,
                        color: scheme.onTertiaryContainer,
                      ),
                      title: Text(
                        'Corbeille · ${formatBytes(_trashSize)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onTertiaryContainer,
                        ),
                      ),
                      subtitle: Text(
                        "$_trashCount élément${_trashCount > 1 ? 's' : ''} · l'espace n'est libéré qu'une fois la corbeille vidée",
                        style: TextStyle(color: scheme.onTertiaryContainer),
                      ),
                      trailing: FilledButton(
                        onPressed: _emptyTrash,
                        child: const Text('Vider'),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TrashPage(trash: _trash),
                          ),
                        );
                        await _measureTrash();
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Lets the user tick what to remove in one category.
class _ReviewPage extends StatefulWidget {
  const _ReviewPage({
    required this.category,
    required this.items,
    required this.trash,
  });
  final CleanCategory category;
  final List<CleanItem> items;
  final Trash trash;

  @override
  State<_ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<_ReviewPage> {
  late final _selected = {
    for (final i in widget.items)
      if (i.preselected) i.path,
  };
  bool _busy = false;

  int get _size => widget.items
      .where((i) => _selected.contains(i.path))
      .fold(0, (sum, i) => sum + i.size);

  Future<void> _clean() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final moved = await cleanToTrash(_selected, widget.trash);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '$moved élément${moved > 1 ? 's' : ''} déplacé${moved > 1 ? 's' : ''} dans la corbeille',
          ),
        ),
      );
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = widget.items;
    final allSelected = _selected.length == items.length;
    final isDuplicates = widget.category == CleanCategory.duplicates;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category.title),
        actions: [
          // Selecting every duplicate would delete the originals too.
          if (!isDuplicates)
            TextButton(
              onPressed: () => setState(() {
                allSelected
                    ? _selected.clear()
                    : _selected.addAll(items.map((i) => i.path));
              }),
              child: Text(allSelected ? 'Tout décocher' : 'Tout cocher'),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                final firstOfGroup =
                    isDuplicates &&
                    (i == 0 || items[i - 1].group != item.group);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (firstOfGroup && i > 0) const Divider(height: 1),
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(item.path),
                      onChanged: (v) => setState(() {
                        v == true
                            ? _selected.add(item.path)
                            : _selected.remove(item.path);
                      }),
                      secondary: Text(
                        formatBytes(item.size),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      subtitle: Text(
                        '${isDuplicates && item == items.firstWhere((o) => o.group == item.group) ? 'Original · ' : ''}${p.basename(p.dirname(item.path))} · ${relativeDate(item.modified)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Material(
            color: scheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selected.length} sélectionné${_selected.length > 1 ? 's' : ''} · ${formatBytes(_size)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _selected.isEmpty || _busy ? null : _clean,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Mettre à la corbeille'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
