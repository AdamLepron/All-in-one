import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import 'documents.dart';

enum _Filter {
  all('Tous'),
  pdf('PDF'),
  text('Texte'),
  office('Bureautique');

  const _Filter(this.label);
  final String label;

  bool accepts(DocFile d) => switch (this) {
    all => true,
    pdf => d.type == DocType.pdf,
    text => d.type == DocType.text,
    office => d.type == DocType.other,
  };
}

/// Document library: recently opened files and every document found on
/// the device.
class ReaderPage extends StatefulWidget {
  const ReaderPage({super.key, this.root = storageRoot});
  final String root;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  List<DocFile>? _docs;
  bool _denied = false;
  _Filter _filter = _Filter.all;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  Future<void> _scan() async {
    if (widget.root == storageRoot && !await ensureFullFileAccess(context)) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final docs = await scanDocuments(widget.root);
    if (mounted) {
      setState(() {
        _docs = docs;
        _denied = false;
      });
    }
  }

  Future<void> _open(String path) async {
    await openDocument(context, path);
    if (mounted) setState(() {}); // refresh the recent row
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final docs = _docs;
    final q = _query.trim().toLowerCase();
    final visible = (docs ?? const <DocFile>[])
        .where(_filter.accepts)
        .where((d) => q.isEmpty || d.name.toLowerCase().contains(q))
        .toList();
    final recents = [
      for (final path in settings.recentDocPaths.take(8))
        if (File(path).existsSync()) path,
    ];

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _searching = false;
            _query = '';
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Rechercher un document',
                    filled: false,
                    border: InputBorder.none,
                  ),
                )
              : const Text('Documents'),
          actions: [
            if (docs != null && docs.isNotEmpty)
              IconButton(
                tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
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
                      const KindIcon(FileKind.document, size: 88),
                      const SizedBox(height: 20),
                      const Text(
                        "L'accès aux fichiers est nécessaire pour retrouver vos documents.",
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _scan,
                        child: const Text("Autoriser l'accès"),
                      ),
                    ],
                  ),
                ),
              )
            : docs == null
            ? const Center(child: CircularProgressIndicator())
            : docs.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Aucun document trouvé sur le téléphone.\nLes PDF et fichiers texte apparaîtront ici.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _scan,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (recents.isNotEmpty && !_searching) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                        child: Text(
                          'Reprendre la lecture',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: recents.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => _RecentCard(
                            path: recents[i],
                            page: settings.docPage(recents[i]),
                            onTap: () => _open(recents[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!_searching)
                      SizedBox(
                        height: 48,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _Filter.values.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final f = _Filter.values[i];
                            return ChoiceChip(
                              showCheckmark: false,
                              label: Text(f.label),
                              selected: f == _filter,
                              onSelected: (_) => setState(() => _filter = f),
                            );
                          },
                        ),
                      ),
                    if (visible.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('Aucun résultat')),
                      ),
                    for (final d in visible)
                      ListTile(
                        leading: _DocIcon(d.path),
                        title: Text(
                          d.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${formatBytes(d.size)} · ${relativeDate(d.modified)} · ${p.basename(p.dirname(d.path))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        onTap: () => _open(d.path),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Coloured badge showing the file extension.
class _DocIcon extends StatelessWidget {
  const _DocIcon(this.path, {this.size = 44});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();
    final color = switch (docTypeOf(path)) {
      DocType.pdf => const Color(0xFFE5484D),
      DocType.text => const Color(0xFF30A46C),
      DocType.other => const Color(0xFF0A84FF),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        ext.length > 4 ? ext.substring(0, 4) : ext,
        style: TextStyle(
          color: color,
          fontSize: size * 0.25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({
    required this.path,
    required this.page,
    required this.onTap,
  });
  final String path;
  final int page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 150,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DocIcon(path, size: 40),
                const Spacer(),
                Text(
                  p.basename(path),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (docTypeOf(path) == DocType.pdf)
                  Text(
                    'Page ${page + 1}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
