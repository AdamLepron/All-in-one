import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../core/modules.dart';
import '../core/settings.dart';

/// Rounded icon badge tinted with the module's family colour.
class ModuleIcon extends StatelessWidget {
  const ModuleIcon(this.module, {super.key, this.size = 48});
  final AppModule module;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = module.family.color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(module.icon, color: color, size: size * 0.54),
    );
  }
}

/// Square tile used in module grids. Long press pins it to the home screen.
class ModuleTile extends StatelessWidget {
  const ModuleTile(this.module, {super.key});
  final AppModule module;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => module.open(context),
        onLongPress: () => showModuleActions(context, module),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModuleIcon(module, size: 44),
                  const Spacer(),
                  if (!module.available) const SoonBadge(),
                ],
              ),
              const Spacer(),
              Text(
                module.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                module.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Bientôt',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Two-column grid of module tiles that sizes itself to its content.
class ModuleGrid extends StatelessWidget {
  const ModuleGrid(this.items, {super.key});
  final List<AppModule> items;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 4 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 128,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => ModuleTile(items[i]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

void showModuleActions(BuildContext context, AppModule module) {
  final settings = context.read<AppSettings>();
  final pinned = settings.isPinned(module.id);
  showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ModuleIcon(module, size: 40),
            title: Text(module.name),
            subtitle: Text(module.description),
          ),
          ListTile(
            leading: Icon(pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(
              pinned ? "Retirer de l'accueil" : "Épingler à l'accueil",
            ),
            onTap: () {
              Navigator.pop(sheet);
              settings.togglePinned(module.id);
            },
          ),
        ],
      ),
    ),
  );
}
