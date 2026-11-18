import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/settings.dart';
import 'sound_level.dart';

/// Sound level meter using the microphone. Nothing is recorded or kept: the
/// samples are measured and thrown away.
class SoundMeter extends StatefulWidget {
  const SoundMeter({super.key, this.source});

  /// Stream of 16-bit mono PCM blocks; the microphone when null (tests give
  /// their own).
  final Stream<Uint8List>? source;

  @override
  State<SoundMeter> createState() => _SoundMeterState();
}

class _SoundMeterState extends State<SoundMeter> {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _sub;
  final _smoother = LevelSmoother();
  final _stats = SoundStats();

  /// The last minute, one point about every 250 ms.
  final _history = <double>[];
  double _db = 0;
  bool _paused = false;
  bool _denied = false;
  DateTime _lastPoint = DateTime.fromMillisecondsSinceEpoch(0);

  double get _calibration =>
      double.tryParse(
        context.read<AppSettings>().raw('soundCalibration') ?? '',
      ) ??
      defaultCalibration;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    Stream<Uint8List> stream;
    if (widget.source != null) {
      stream = widget.source!;
    } else {
      final recorder = _recorder = AudioRecorder();
      if (!await recorder.hasPermission()) {
        if (mounted) setState(() => _denied = true);
        return;
      }
      stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
    }
    _sub = stream.listen(_onBlock);
  }

  void _onBlock(Uint8List block) {
    if (_paused || !mounted) return;
    final db = _smoother.add(
      dbFromDbfs(dbfsOfPcm16(block), calibration: _calibration),
    );
    _stats.add(db);
    final now = DateTime.now();
    if (now.difference(_lastPoint) > const Duration(milliseconds: 250)) {
      _lastPoint = now;
      _history.add(db);
      if (_history.length > 240) _history.removeAt(0);
    }
    setState(() => _db = db);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _recorder?.stop();
    _recorder?.dispose();
    super.dispose();
  }

  void _calibrate() {
    final settings = context.read<AppSettings>();
    var value = _calibration;
    showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Étalonnage'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Les micros de téléphone ne sont pas étalonnés. Comparez avec un sonomètre ou une application de référence et ajustez : le niveau affiché change de ce décalage.',
              ),
              Slider(
                min: 70,
                max: 110,
                divisions: 80,
                label: value.toStringAsFixed(1),
                value: value.clamp(70, 110),
                onChanged: (v) => setLocal(() => value = v),
              ),
              Text(
                'Décalage : ${(value - defaultCalibration).toStringAsFixed(1)} dB',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                settings.setRaw('soundCalibration', '$defaultCalibration');
                Navigator.pop(dialog);
              },
              child: const Text('Par défaut'),
            ),
            FilledButton(
              onPressed: () {
                settings.setRaw('soundCalibration', '$value');
                Navigator.pop(dialog);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    if (_denied) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            "L'accès au microphone est nécessaire pour mesurer le bruit. Rien n'est enregistré.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final color = _db < 60
        ? scheme.primary
        : _db < 85
        ? scheme.tertiary
        : scheme.error;
    String fmt(double? v) => v == null ? '—' : v.toStringAsFixed(0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Semantics(
          liveRegion: true,
          label: '${_db.round()} décibels, ${describeLevel(_db)}',
          child: Column(
            children: [
              Text(
                _db.toStringAsFixed(0),
                style: text.displayLarge?.copyWith(
                  fontSize: 96,
                  fontWeight: FontWeight.w300,
                  color: color,
                ),
              ),
              Text('dB', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                describeLevel(_db),
                style: text.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            minHeight: 12,
            value: (_db / 120).clamp(0.0, 1.0),
            color: color,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 120,
          child: CustomPaint(
            painter: _HistoryPainter(
              _history,
              scheme.primary,
              scheme.outlineVariant,
            ),
            size: Size.infinite,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Stat('Min', fmt(_stats.min)),
            _Stat('Moyen', fmt(_stats.average)),
            _Stat('Max', fmt(_stats.max)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            FilledButton.tonalIcon(
              icon: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              ),
              label: Text(_paused ? 'Reprendre' : 'Pause'),
              onPressed: () => setState(() => _paused = !_paused),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Remettre à zéro'),
              onPressed: () => setState(() {
                _stats.reset();
                _history.clear();
              }),
            ),
            TextButton.icon(
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Étalonner'),
              onPressed: _calibrate,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Mesure indicative : le micro d\'un téléphone n\'est pas un sonomètre professionnel.',
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label : $value décibels',
    excludeSemantics: true,
    child: Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter(this.values, this.line, this.grid);
  final List<double> values;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final db in [30, 60, 90]) {
      final y = size.height * (1 - db / 120);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / 239;
      final y = size.height * (1 - (values[i] / 120).clamp(0.0, 1.0));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => true;
}
