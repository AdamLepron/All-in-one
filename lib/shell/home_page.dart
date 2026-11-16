import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/modules.dart';
import '../core/settings.dart';
import '../modules/notes/notes_page.dart';
import '../modules/notes/notes_store.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Bonne nuit';
    if (hour < 18) return 'Bonjour';
    return 'Bonsoir';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final notes = context.watch<NotesStore>().notes;
    final pinned = [
      for (final id in settings.pinned) ...modules.where((m) => m.id == id),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_greeting),
        actions: [
          IconButton(
            tooltip: 'Réglages',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (notes.isNotEmpty) ...[
            const SectionTitle('Reprendre'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ResumeCard(
                note: notes.reduce(
                  (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
                ),
              ),
            ),
          ],
          const SectionTitle('Raccourcis'),
          if (pinned.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Appuyez longuement sur un module pour l\'épingler ici.',
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 4,
                childAspectRatio: 0.82,
                children: [for (final m in pinned) _Shortcut(m)],
              ),
            ),
          SectionTitle(
            'Notes récentes',
            trailing: TextButton(
              onPressed: () => moduleById('notes').open(context),
              child: const Text('Tout voir'),
            ),
          ),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: ModuleIcon(moduleById('notes')),
                  title: const Text('Aucune note pour le moment'),
                  subtitle: const Text('Appuyez pour écrire la première'),
                  onTap: () => openNote(context),
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: notes.length.clamp(0, 8),
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(
                  width: 180,
                  child: NoteCard(note: notes[i], maxLines: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          ),
        ),
        child: InkWell(
          onTap: () => openNote(context, note),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.sticky_note_2_rounded,
                  size: 36,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dernière note modifiée',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note.title.isEmpty ? note.body : note.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.module);
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => module.open(context),
      onLongPress: () => showModuleActions(context, module),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Opacity(
            opacity: module.available ? 1 : 0.5,
            child: ModuleIcon(module, size: 56),
          ),
          const SizedBox(height: 6),
          Text(
            module.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
