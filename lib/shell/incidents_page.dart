import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/crash_log.dart';

/// Shows the local incident journal, to read or send to the developer.
class IncidentsPage extends StatefulWidget {
  const IncidentsPage({super.key});

  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  late String _text = CrashLog.read();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Journal d'incidents"),
        actions: [
          if (_text.isNotEmpty) ...[
            IconButton(
              tooltip: 'Copier',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _text));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Journal copié')));
              },
            ),
            IconButton(
              tooltip: 'Partager',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text: _text,
                  subject: "Journal d'incidents All-in-One",
                ),
              ),
            ),
            IconButton(
              tooltip: 'Effacer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                CrashLog.clear();
                setState(() => _text = '');
              },
            ),
          ],
        ],
      ),
      body: _text.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Aucun incident enregistré',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Quand l'application rencontre une erreur, elle la note ici, sur ce téléphone seulement. "
                      'Rien n\'est envoyé : vous choisissez de le partager ou non.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : SelectionArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    _text,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
