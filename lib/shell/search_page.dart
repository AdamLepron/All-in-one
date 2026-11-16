import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/modules.dart';
import '../core/util.dart';
import '../modules/notes/notes_page.dart';
import '../modules/notes/notes_store.dart';
import 'widgets.dart';

/// Universal search across modules and note contents.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final store = context.watch<NotesStore>();
    final q = _query.trim().toLowerCase();
    final moduleHits = q.isEmpty
        ? <AppModule>[]
        : modules
            .where((m) =>
                m.name.toLowerCase().contains(q) ||
                m.description.toLowerCase().contains(q))
            .toList();
    final noteHits = store.search(q);

    return Scaffold(
      appBar: AppBar(title: const Text('Recherche')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Modules, notes…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: q.isEmpty
                ? _Hint(
                    icon: Icons.search,
                    text: 'Cherchez un module ou le contenu de vos notes',
                    color: scheme.outline,
                  )
                : moduleHits.isEmpty && noteHits.isEmpty
                    ? _Hint(
                        icon: Icons.search_off,
                        text: 'Aucun résultat pour « ${_query.trim()} »',
                        color: scheme.outline,
                      )
                    : ListView(
                        children: [
                          if (moduleHits.isNotEmpty) const _GroupLabel('Modules'),
                          for (final m in moduleHits)
                            ListTile(
                              leading: ModuleIcon(m, size: 40),
                              title: Text(m.name),
                              subtitle: Text(m.description),
                              trailing: m.available ? null : const SoonBadge(),
                              onTap: () => m.open(context),
                            ),
                          if (noteHits.isNotEmpty) const _GroupLabel('Notes'),
                          for (final n in noteHits)
                            ListTile(
                              leading: ModuleIcon(moduleById('notes'), size: 40),
                              title: Text(
                                n.title.isEmpty ? 'Sans titre' : n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                n.body.isEmpty ? relativeDate(n.updatedAt) : n.body,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => openNote(context, n),
                            ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
