import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform.dart';

enum _Tool {
  torch('Lampe', Icons.flashlight_on_rounded),
  compass('Boussole', Icons.explore_rounded),
  level('Niveau', Icons.straighten_rounded),
  ruler('Règle', Icons.square_foot_rounded);

  const _Tool(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Torch, compass, spirit level and ruler.
class SensorsPage extends StatefulWidget {
  const SensorsPage({super.key, this.initialTool = 0});
  final int initialTool;

  @override
  State<SensorsPage> createState() => _SensorsPageState();
}

class _SensorsPageState extends State<SensorsPage> {
  late _Tool _tool = _Tool.values[widget.initialTool];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_tool.label)),
      body: switch (_tool) {
        _Tool.torch => const _Torch(),
        _Tool.compass => const _Compass(),
        _Tool.level => const _Level(),
        _Tool.ruler => const _Ruler(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tool.index,
        onDestinationSelected: (i) => setState(() => _tool = _Tool.values[i]),
        destinations: [
          for (final t in _Tool.values)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

class _Torch extends StatefulWidget {
  const _Torch();

  @override
  State<_Torch> createState() => _TorchState();
}

class _TorchState extends State<_Torch> {
  bool _on = false;
  bool? _hasFlash;

  /// Without a flash, the screen itself lights up in white.
  bool get _screenLight => _on && _hasFlash == false;

  @override
  void initState() {
    super.initState();
    MediaChannel.hasTorch().then((v) {
      if (mounted) setState(() => _hasFlash = v);
    });
  }

  @override
  void dispose() {
    if (_on) _apply(false);
    super.dispose();
  }

  Future<void> _apply(bool on) async {
    if (_hasFlash == true && await MediaChannel.setTorch(on)) return;
    // Flash missing or busy: use the screen at full brightness.
    await MediaChannel.setBrightness(on ? 1 : -1);
    await MediaChannel.keepScreenOn(on);
  }

  Future<void> _toggle() async {
    HapticFeedback.mediumImpact();
    final on = !_on;
    setState(() => _on = on);
    await _apply(on);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: _screenLight ? Colors.white : scheme.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: _on
                  ? const Color(0xFFFFC53D)
                  : scheme.surfaceContainerHighest,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              elevation: _on ? 12 : 0,
              shadowColor: const Color(0xFFFFC53D),
              child: InkWell(
                onTap: _toggle,
                child: SizedBox(
                  width: 180,
                  height: 180,
                  child: Icon(
                    _on
                        ? Icons.flashlight_on_rounded
                        : Icons.flashlight_off_rounded,
                    size: 84,
                    color: _on ? Colors.black : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _on ? 'Allumée' : 'Éteinte',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _screenLight ? Colors.black : null,
              ),
            ),
            if (_hasFlash == false)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
                child: Text(
                  "Pas de flash sur cet appareil : l'écran sert de lampe.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _screenLight ? Colors.black54 : null),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Subscribes to the orientation sensor and hands readings to [builder].
class _Orientation extends StatefulWidget {
  const _Orientation({required this.builder});
  final Widget Function(BuildContext, List<double> angles) builder;

  @override
  State<_Orientation> createState() => _OrientationState();
}

class _OrientationState extends State<_Orientation> {
  StreamSubscription<List<double>>? _subscription;
  List<double>? _angles;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subscription = MediaChannel.orientation().listen(
      (a) => setState(() => _angles = a),
      onError: (Object _) => setState(() => _failed = true),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final angles = _angles;
    if (angles != null) return widget.builder(context, angles);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _failed
            ? const Text(
                "Cet appareil n'a pas de capteur d'orientation.",
                textAlign: TextAlign.center,
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

const _cardinals = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];

/// "N", "NE"… for a heading in degrees.
String cardinal(double heading) =>
    _cardinals[((heading % 360) / 45).round() % 8];

class _Compass extends StatelessWidget {
  const _Compass();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Orientation(
      builder: (context, angles) {
        final heading = angles[0];
        return Column(
          children: [
            const SizedBox(height: 32),
            Text(
              '${heading.round() % 360}°',
              style: text.displayLarge?.copyWith(fontWeight: FontWeight.w300),
            ),
            Text(
              cardinal(heading),
              style: text.headlineSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    painter: _DialPainter(
                      heading: heading,
                      color: scheme.onSurface,
                      muted: scheme.outline,
                      north: scheme.error,
                      accent: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: Text(
                'Tenez le téléphone à plat. Éloignez-le des aimants et décrivez un 8 pour le calibrer.',
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.heading,
    required this.color,
    required this.muted,
    required this.north,
    required this.accent,
  });

  final double heading;
  final Color color;
  final Color muted;
  final Color north;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    // Fixed marker showing where the top of the phone points.
    final marker = Path()
      ..moveTo(center.dx, center.dy - radius - 4)
      ..lineTo(center.dx - 9, center.dy - radius - 20)
      ..lineTo(center.dx + 9, center.dy - radius - 20)
      ..close();
    canvas.drawPath(marker, Paint()..color = accent);

    // The dial turns against the heading so that N stays on north.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-heading * math.pi / 180);
    for (var deg = 0; deg < 360; deg += 5) {
      final major = deg % 30 == 0;
      final a = deg * math.pi / 180;
      final outer = Offset(math.sin(a), -math.cos(a)) * radius;
      final inner =
          Offset(math.sin(a), -math.cos(a)) * (radius - (major ? 16 : 8));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = deg == 0
              ? north
              : major
              ? color
              : muted
          ..strokeWidth = major ? 2.5 : 1,
      );
    }
    for (var i = 0; i < 4; i++) {
      final label = const ['N', 'E', 'S', 'O'][i];
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: radius * 0.2,
            fontWeight: FontWeight.w800,
            color: i == 0 ? north : color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.rotate(i * math.pi / 2);
      painter.paint(canvas, Offset(-painter.width / 2, -radius + 26));
      canvas.restore();
    }
    canvas.restore();
    canvas.drawCircle(center, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.heading != heading || old.color != color;
}

class _Level extends StatelessWidget {
  const _Level();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return _Orientation(
      builder: (context, angles) {
        // Pitch tilts front to back, roll side to side; both are 0 when flat.
        final pitch = angles[1];
        final roll = angles[2];
        final flat = pitch.abs() < 1 && roll.abs() < 1;
        final color = flat ? const Color(0xFF30A46C) : scheme.primary;
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: CustomPaint(
                    painter: _BubblePainter(
                      // 30° of tilt brings the bubble to the rim.
                      dx: (roll / 30).clamp(-1.0, 1.0),
                      dy: (-pitch / 30).clamp(-1.0, 1.0),
                      bubble: color,
                      ring: scheme.outline,
                      fill: scheme.surfaceContainer,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Angle(label: 'Gauche / droite', value: roll, color: color),
                _Angle(label: 'Avant / arrière', value: pitch, color: color),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
              child: Text(
                flat
                    ? 'À niveau'
                    : 'Posez le téléphone à plat sur la surface à vérifier.',
                textAlign: TextAlign.center,
                style: flat
                    ? text.titleLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      )
                    : text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Angle extends StatelessWidget {
  const _Angle({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          '${value.abs().toStringAsFixed(1).replaceAll('.', ',')}°',
          style: text.displaySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w300,
          ),
        ),
        Text(label, style: text.labelMedium),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter({
    required this.dx,
    required this.dy,
    required this.bubble,
    required this.ring,
    required this.fill,
  });

  final double dx;
  final double dy;
  final Color bubble;
  final Color ring;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bubbleRadius = radius * 0.16;
    final line = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    canvas.drawCircle(center, radius, Paint()..color = fill);
    canvas.drawCircle(center, radius, line);
    canvas.drawCircle(center, bubbleRadius + 6, line);
    canvas.drawLine(
      center.translate(-radius, 0),
      center.translate(radius, 0),
      line,
    );
    canvas.drawLine(
      center.translate(0, -radius),
      center.translate(0, radius),
      line,
    );

    // Keep the bubble inside the dial.
    var offset = Offset(dx, dy) * (radius - bubbleRadius);
    final limit = radius - bubbleRadius;
    if (offset.distance > limit) offset = offset / offset.distance * limit;
    canvas.drawCircle(center + offset, bubbleRadius, Paint()..color = bubble);
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.dx != dx || old.dy != dy || old.bubble != bubble;
}

class _Ruler extends StatefulWidget {
  const _Ruler();

  @override
  State<_Ruler> createState() => _RulerState();
}

class _RulerState extends State<_Ruler> {
  /// Logical pixels per millimetre along the screen's long side.
  double? _perMm;

  @override
  void initState() {
    super.initState();
    MediaChannel.dpi().then((dpi) {
      if (!mounted) return;
      setState(
        () => _perMm = dpi == null ? 160 / 25.4 : dpi.ydpi / dpi.density / 25.4,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final perMm = _perMm;
    if (perMm == null) return const Center(child: CircularProgressIndicator());
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _RulerPainter(
              perMm: perMm,
              color: scheme.onSurface,
              muted: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: 170,
              child: Text(
                "Posez l'objet contre le bord gauche, à partir du haut de la règle.\n\nLa précision dépend de l'écran : comparez avec une règle réelle avant une mesure importante.",
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.perMm,
    required this.color,
    required this.muted,
  });
  final double perMm;
  final Color color;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    for (var mm = 0; mm * perMm <= size.height; mm++) {
      final y = mm * perMm;
      final length = mm % 10 == 0
          ? 44.0
          : mm % 5 == 0
          ? 30.0
          : 18.0;
      canvas.drawLine(Offset(0, y), Offset(length, y), paint);
      if (mm % 10 == 0 && mm > 0) {
        final label = TextPainter(
          text: TextSpan(
            text: '${mm ~/ 10}',
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(52, y - label.height / 2));
      }
    }
    final unit = TextPainter(
      text: TextSpan(
        text: 'cm',
        style: TextStyle(fontFamily: 'Roboto', fontSize: 13, color: muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unit.paint(canvas, const Offset(52, 4));
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.perMm != perMm || old.color != color;
}
