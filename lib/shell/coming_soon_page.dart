import 'package:material_ui/material_ui.dart';

import '../core/modules.dart';
import 'widgets.dart';

/// Placeholder shown for modules that are planned but not built yet.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.module});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(module.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ModuleIcon(module, size: 96),
              const SizedBox(height: 24),
              Text(
                module.name,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                module.description,
                style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Text(
                'Ce module arrive dans une prochaine étape.',
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
