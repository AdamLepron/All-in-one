import 'package:material_ui/material_ui.dart';

import '../core/l10n.dart';
import '../core/adaptive.dart';
import '../core/modules.dart';
import '../core/theme.dart';
import '../core/widget_sync.dart';

import 'package:provider/provider.dart';

import '../core/platform.dart';
import '../modules/calendar/event_editor_page.dart';
import '../modules/share/incoming.dart';
import '../modules/share/share_sheet.dart';
import '../modules/docs/document_editor_page.dart';
import '../modules/ads/ad_widgets.dart';
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
  late final WidgetSync _widgets;

  @override
  void initState() {
    super.initState();
    _widgets = WidgetSync(context.read<OrganizerStore>())..start();
    // Content shared with the app: while it runs, and what arrived before.
    MediaChannel.onShared(_onShared);
    MediaChannel.takeShared().then((content) {
      if (content != null) _onShared(content);
    });
  }

  @override
  void dispose() {
    _widgets.dispose();
    super.dispose();
  }

  void _onShared(Map<Object?, Object?> content) {
    // A tap on a home-screen widget.
    if (content['action'] == 'open') {
      if (!mounted) return;
      switch (content['target']) {
        case 'new_note':
          openNote(context);
        case 'new_task':
          showTaskEditor(context);
      }
      return;
    }
    final incoming = Incoming.fromMap(content);
    if (incoming == null || !mounted) return;
    handleIncoming(context, incoming);
  }

  static const _pages = <Widget>[
    HomePage(),
    FamilyPage(Family.media, title: 'Médias'),
    FamilyPage(Family.productivity, title: 'Documents'),
    FamilyPage(Family.tools, title: 'Outils'),
    SearchPage(),
  ];

  static const _destinations = <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Accueil'),
    (Icons.play_circle_outline, Icons.play_circle_rounded, 'Médias'),
    (Icons.folder_outlined, Icons.folder_rounded, 'Documents'),
    (Icons.widgets_outlined, Icons.widgets_rounded, 'Outils'),
    (Icons.search, Icons.search_rounded, 'Recherche'),
  ];

  @override
  Widget build(BuildContext context) {
    // Wide windows (tablets, landscape) get a side rail instead of the bar.
    final rail = useRail(MediaQuery.sizeOf(context).width);
    final body = IndexedStack(index: _index, children: _pages);
    return PopScope(
      // Back returns to the home tab before leaving the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
        body: rail
            ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (i) => setState(() => _index = i),
                    leading: _index == 0
                        ? FloatingActionButton(
                            tooltip: tr('Créer'),
                            onPressed: () => _showCreateSheet(context),
                            child: const Icon(Icons.add),
                          )
                        : const SizedBox(height: 56),
                    destinations: [
                      for (final (icon, selected, label) in _destinations)
                        NavigationRailDestination(
                          icon: Icon(icon),
                          selectedIcon: Icon(selected),
                          label: Text(tr(label)),
                        ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
        floatingActionButton: !rail && _index == 0
            ? FloatingActionButton.extended(
                onPressed: () => _showCreateSheet(context),
                icon: const Icon(Icons.add),
                label: Text(tr('Créer')),
              )
            : null,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AdBanner(),
            const MiniPlayer(),
            if (!rail)
              NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: [
                  for (final (icon, selected, label) in _destinations)
                    NavigationDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(selected),
                      label: tr(label),
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
              title: Text(tr('Nouvelle note')),
              onTap: () {
                Navigator.pop(sheet);
                openNote(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('tasks'), size: 40),
              title: Text(tr('Nouvelle tâche')),
              onTap: () {
                Navigator.pop(sheet);
                showTaskEditor(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('calendar'), size: 40),
              title: Text(tr('Nouvel événement')),
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
              title: Text(tr('Enregistrement audio')),
              onTap: () {
                Navigator.pop(sheet);
                moduleById('recorder').open(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('scanner'), size: 40),
              title: Text(tr('Scanner un document')),
              onTap: () {
                Navigator.pop(sheet);
                moduleById('scanner').open(context);
              },
            ),
            ListTile(
              leading: ModuleIcon(moduleById('doc_editor'), size: 40),
              title: Text(tr('Nouveau document')),
              onTap: () {
                Navigator.pop(sheet);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DocumentEditorPage(),
                  ),
                );
              },
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
      appBar: AppBar(title: Text(tr(title))),
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
          const NativeAdCard(),
        ],
      ),
    );
  }
}
