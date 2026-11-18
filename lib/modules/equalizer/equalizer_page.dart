import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/util.dart';
import 'eq_model.dart';
import 'equalizer_controller.dart';

class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget title(String s) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Text(
        s,
        style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

    final balanceLabel = eq.balance == 0
        ? 'Centré'
        : '${eq.balance < 0 ? 'Gauche' : 'Droite'} ${(eq.balance.abs() * 100).round()} %';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Égaliseur'),
        actions: [
          IconButton(
            tooltip: 'Réinitialiser',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: eq.reset,
          ),
          Semantics(
            label: "Activer l'égaliseur",
            child: Switch(value: eq.enabled, onChanged: eq.setEnabled),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (!eq.attached)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Card(
                color: scheme.secondaryContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.info_outline,
                    color: scheme.onSecondaryContainer,
                  ),
                  title: Text(
                    'Lancez un morceau dans Musique : vos réglages s\'appliqueront aussitôt.',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount:
                  eqPresets.length +
                  eq.saved.length +
                  1 + // "save" chip
                  (eq.preset == null ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                // A custom curve gets its own leading chip.
                if (eq.preset == null) {
                  if (i == 0) {
                    return ChoiceChip(
                      showCheckmark: false,
                      label: const Text('Personnalisé'),
                      selected: true,
                      onSelected: (_) {},
                    );
                  }
                  i--;
                }
                if (i < eqPresets.length) {
                  final p = eqPresets[i];
                  return ChoiceChip(
                    showCheckmark: false,
                    label: Text(p.name),
                    selected: p.name == eq.preset,
                    onSelected: (_) => eq.selectPreset(p),
                  );
                }
                i -= eqPresets.length;
                if (i < eq.saved.length) {
                  final m = eq.saved[i];
                  final name = m['name']! as String;
                  return GestureDetector(
                    onLongPress: () => _confirmDelete(context, eq, name),
                    child: Semantics(
                      onLongPressHint: 'Supprimer ce préréglage',
                      child: ChoiceChip(
                        avatar: const Icon(Icons.person_outline, size: 16),
                        showCheckmark: false,
                        label: Text(name),
                        selected: name == eq.preset,
                        onSelected: (_) => eq.selectSaved(m),
                      ),
                    ),
                  );
                }
                return ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Enregistrer'),
                  onPressed: () => _saveDialog(context, eq),
                );
              },
            ),
          ),
          if (eq.output != null)
            SwitchListTile(
              title: Text('Profil : ${eq.outputLabel}'),
              subtitle: const Text(
                'Retrouver ces réglages à chaque fois que cet appareil audio est utilisé',
              ),
              value: eq.outputHasProfile,
              onChanged: eq.setOutputProfile,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Card(
              child: Opacity(
                opacity: eq.enabled ? 1 : 0.5,
                child: SizedBox(height: 300, child: _Bands(eq: eq)),
              ),
            ),
          ),
          title('Balance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Text('G', style: TextStyle(fontWeight: FontWeight.w700)),
                Expanded(
                  child: Slider(
                    min: -1,
                    max: 1,
                    value: eq.balance,
                    onChanged: eq.balanceSupported ? eq.setBalance : null,
                  ),
                ),
                const Text('D', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    eq.balanceSupported
                        ? balanceLabel
                        : 'Non disponible sur cet appareil (Android 9 requis)',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                if (eq.balance != 0)
                  TextButton(
                    onPressed: () => eq.setBalance(0),
                    child: const Text('Recentrer'),
                  ),
              ],
            ),
          ),
          title('Effets'),
          _Effect(
            icon: Icons.speaker_rounded,
            label: 'Basses',
            value: eq.bass,
            onChanged: eq.setBass,
          ),
          _Effect(
            icon: Icons.surround_sound_rounded,
            label: 'Élargissement stéréo',
            value: eq.widening,
            onChanged: eq.setWidening,
          ),
          _Effect(
            icon: Icons.volume_up_rounded,
            label: 'Amplification',
            value: eq.gain,
            suffix: '+${formatNumber(eq.gain * 10, digits: 2)} dB',
            onChanged: eq.setGain,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              "Les réglages s'appliquent à la musique lue dans l'application.",
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical sliders, one per band, with the response curve drawn behind.
class _Bands extends StatelessWidget {
  const _Bands({required this.eq});
  final EqualizerController eq;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              for (final level in eq.levels)
                Expanded(
                  child: Text(
                    '${level > 0 ? '+' : ''}${formatNumber(level, digits: 3)}',
                    textAlign: TextAlign.center,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: CustomPaint(
              painter: _CurvePainter(
                levels: eq.levels,
                min: eq.minLevel,
                max: eq.maxLevel,
                color: scheme.primary,
                grid: scheme.outlineVariant,
              ),
              child: Row(
                children: [
                  for (var i = 0; i < eq.bands.length; i++)
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            // The curve already shows the level.
                            activeTrackColor: scheme.outlineVariant,
                            inactiveTrackColor: scheme.outlineVariant,
                            overlayShape: SliderComponentShape.noOverlay,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 9,
                            ),
                          ),
                          child: Slider(
                            min: eq.minLevel,
                            max: eq.maxLevel,
                            divisions: ((eq.maxLevel - eq.minLevel) * 2)
                                .round(),
                            value: eq.levels[i].clamp(eq.minLevel, eq.maxLevel),
                            onChanged: (v) => eq.setBand(i, v),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              for (final hz in eq.bands)
                Expanded(
                  child: Text(
                    bandLabel(hz),
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          Text('Hz', style: text.labelSmall?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.levels,
    required this.min,
    required this.max,
    required this.color,
    required this.grid,
  });

  final List<double> levels;
  final double min;
  final double max;
  final Color color;
  final Color grid;

  // Matches the slider's own inset so the curve passes through the thumbs.
  static const _inset = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final usable = size.height - 2 * _inset;
    double y(double db) => _inset + usable * (1 - (db - min) / (max - min));
    final step = size.width / levels.length;

    canvas.drawLine(
      Offset(0, y(0)),
      Offset(size.width, y(0)),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final points = [
      for (var i = 0; i < levels.length; i++)
        Offset(step * (i + 0.5), y(levels[i].clamp(min, max))),
    ];
    final line = Path()..moveTo(0, points.first.dy);
    line.lineTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final mid = (points[i - 1].dx + points[i].dx) / 2;
      line.cubicTo(
        mid,
        points[i - 1].dy,
        mid,
        points[i].dy,
        points[i].dx,
        points[i].dy,
      );
    }
    line.lineTo(size.width, points.last.dy);

    final area = Path.from(line)
      ..lineTo(size.width, y(0))
      ..lineTo(0, y(0))
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.levels != levels ||
      old.color != color ||
      old.min != min ||
      old.max != max;
}

class _Effect extends StatelessWidget {
  const _Effect({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(label)),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        suffix ?? '${(value * 100).round()} %',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderThemeData(
                    overlayShape: SliderComponentShape.noOverlay,
                    padding: const EdgeInsets.fromLTRB(0, 10, 16, 10),
                  ),
                  child: Slider(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _saveDialog(BuildContext context, EqualizerController eq) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Enregistrer ce réglage'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nom du préréglage'),
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  if (name != null) eq.saveCurrent(name);
}

Future<void> _confirmDelete(
  BuildContext context,
  EqualizerController eq,
  String name,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Supprimer « $name » ?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Supprimer'),
        ),
      ],
    ),
  );
  if (ok == true) eq.deleteSaved(name);
}
