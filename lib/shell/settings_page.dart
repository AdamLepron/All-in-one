import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/crash_log.dart';
import '../core/settings.dart';
import '../modules/backup/backup_page.dart';
import 'incidents_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget label(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
      child: Text(
        s,
        style: text.titleSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        children: [
          label('Thème'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Système'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Clair'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Sombre'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.themeMode = s.first,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Noir AMOLED'),
            subtitle: const Text('Fond noir pur en thème sombre'),
            value: settings.amoled,
            onChanged: (v) => settings.amoled = v,
          ),
          label("Couleur d'accent"),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < accentChoices.length; i++)
                  Semantics(
                    label: 'Couleur ${accentNames[i]}',
                    button: true,
                    selected: settings.accentIndex == i,
                    excludeSemantics: true,
                    onTap: () => settings.accentIndex = i,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => settings.accentIndex = i,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentChoices[i],
                          shape: BoxShape.circle,
                        ),
                        child: settings.accentIndex == i
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          label('Données'),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Sauvegarde et restauration'),
            subtitle: const Text('Notes, tâches, événements, réglages'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const BackupPage())),
          ),
          label('Diagnostic'),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text("Journal d'incidents"),
            subtitle: Text(
              CrashLog.count == 0
                  ? 'Aucun incident'
                  : '${CrashLog.count} incident${CrashLog.count > 1 ? 's' : ''} enregistré${CrashLog.count > 1 ? 's' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const IncidentsPage()),
              );
              // The count may have changed (journal cleared).
              if (context.mounted) (context as Element).markNeedsBuild();
            },
          ),
          label('À propos'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('All-in-One'),
            subtitle: Text('Version 1.6.0 · Finitions des utilitaires'),
          ),
        ],
      ),
    );
  }
}
