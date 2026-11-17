import 'package:material_ui/material_ui.dart';

import '../core/modules.dart';
import '../core/theme.dart';
import '../modules/calendar/event_editor_page.dart';
import '../modules/music/mini_player.dart';
import '../modules/notes/notes_page.dart';
import '../modules/tasks/organizer_store.dart';
import '../modules/tasks/tasks_page.dart';
import 'home_page.dart';
import 'search_page.dart';
import 'widgets.dart';

/// Root screen: five bottom tabs, each keeping its own state.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = <Widget>[
    HomePage(),
    FamilyPage(Family.media, title: 'Médias'),
    FamilyPage(Family.productivity, title: 'Documents'),
    FamilyPage(Family.tools, title: 'Outils'),
    SearchPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back returns to the home tab before leaving the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: IndexedStack(index: _index, children: _pages),
        floatingActionButton: _index == 0
            ? FloatingActionButton.extended(
                onPressed: () => _showCreateSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Créer'),
              )
            : null,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Accueil',
                ),
                NavigationDestination(
                  icon: Icon(Icons.play_circle_outline),
                  selectedIcon: Icon(Icons.play_circle_rounded),
                  label: 'Médias',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Documents',
                ),
                NavigationDestination(
                  icon: Icon(Icons.widgets_outlined),
                  selectedIcon: Icon(Icons.widgets_rounded),
                  label: 'Outils',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  selectedIcon: Icon(Icons.search_rounded),
                  label: 'Recherche',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ModuleIcon(moduleById('notes'), size: 40),
              title: const Text('Nouvelle note'),
              onTap: () {
                Navigator.pop(sheet);
                openNote(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('tasks'), size: 40),
              title: const Text('Nouvelle tâche'),
              onTap: () {
                Navigator.pop(sheet);
                showTaskEditor(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('calendar'), size: 40),
              title: const Text('Nouvel événement'),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EventEditorPage(day: dayOf(DateTime.now())),
                  ),
                );
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('recorder'), size: 40),
              title: const Text('Enregistrement audio'),
              onTap: () {
                Navigator.pop(sheet);
                moduleById('recorder').open(context);
              },
            ),
            for (final id in const ['doc_editor', 'scanner'])
              ListTile(
                enabled: false,
                leading: ModuleIcon(moduleById(id), size: 40),
                title: Text(
                  const {
                    'doc_editor': 'Nouveau document',
                    'scanner': 'Scanner un document',
                  }[id]!,
                ),
                trailing: const SoonBadge(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Tab listing every module of one family.
class FamilyPage extends StatelessWidget {
  const FamilyPage(this.family, {super.key, required this.title});
  final Family family;
  final String title;

  @override
  Widget build(BuildContext context) {
    final items = modulesOf(family);
    final ready = items.where((m) => m.available).toList();
    final soon = items.where((m) => !m.available).toList();
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (ready.isNotEmpty) ...[
            const SizedBox(height: 8),
            ModuleGrid(ready),
          ],
          if (soon.isNotEmpty) ...[
            SectionTitle(ready.isEmpty ? 'En préparation' : 'Prochainement'),
            ModuleGrid(soon),
          ],
        ],
      ),
    );
  }
}
