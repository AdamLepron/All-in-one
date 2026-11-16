import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/util.dart';
import '../clock/clock_controller.dart' show formatStopwatch;
import '../files/files_ui.dart' show askName, showMessage;
import '../music/mini_player.dart';
import '../music/music_controller.dart';
import '../music/song.dart';
import 'recorder_controller.dart';

const _red = Color(0xFFE5484D);

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final recorder = context.read<RecorderController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => recorder.load());
    // Refreshes the elapsed time while recording.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (recorder.state == RecorderState.recording) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final recorder = context.read<RecorderController>();
    context.read<MusicController>().pause();
    if (!await recorder.start() && mounted) {
      showMessage(
        context,
        "L'accès au micro est nécessaire pour enregistrer",
        action: SnackBarAction(label: 'Réglages', onPressed: openAppSettings),
      );
    }
  }

  void _play(Recording r) {
    context.read<MusicController>().play(
      [
        Song(
          // Negative ids never collide with the media library.
          id: -(r.path.hashCode.abs() + 1),
          title: r.name,
          artist: 'Enregistrement',
          album: 'Enregistreur',
          albumId: -1,
          duration: r.duration,
          uri: Uri.file(r.path).toString(),
          path: r.path,
        ),
      ],
      0,
      shuffled: false,
    );
  }

  void _actions(Recording r) {
    final recorder = context.read<RecorderController>();
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Renommer'),
              onTap: () async {
                Navigator.pop(sheet);
                final name = await askName(
                  context,
                  title: 'Renommer',
                  initial: r.name,
                  action: 'Renommer',
                );
                if (name == null) return;
                if (!await recorder.rename(r, name) && mounted) {
                  showMessage(context, 'Un enregistrement porte déjà ce nom');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Partager'),
              onTap: () {
                Navigator.pop(sheet);
                SharePlus.instance.share(ShareParams(files: [XFile(r.path)]));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Supprimer'),
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('Supprimer cet enregistrement ?'),
                    content: Text(
                      '« ${r.name} » sera supprimé définitivement.',
                    ),
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
                if (ok == true) await recorder.delete(r);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recorder = context.watch<RecorderController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = recorder.state != RecorderState.idle;
    final playingPath = context.select<MusicController, String?>(
      (m) => m.current?.path,
    );

    return PopScope(
      // Leaving mid-recording would lose track of it: ask to stop first.
      canPop: !active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          showMessage(context, "Terminez l'enregistrement avant de quitter");
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Enregistreur')),
        bottomNavigationBar: active
            ? null
            : const SafeArea(child: MiniPlayer()),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    children: [
                      Text(
                        formatStopwatch(recorder.elapsed),
                        style: text.displayMedium?.copyWith(
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: recorder.state == RecorderState.recording
                              ? _red
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 72,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _WavePainter(
                            levels: List.of(recorder.waveform),
                            color: active ? _red : scheme.outlineVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!active)
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Standard'),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('Sans perte'),
                            ),
                          ],
                          selected: {recorder.lossless},
                          onSelectionChanged: (s) =>
                              recorder.setLossless(s.first),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (active)
                            IconButton.outlined(
                              tooltip: 'Abandonner',
                              iconSize: 28,
                              icon: const Icon(Icons.close),
                              onPressed: () => recorder.stop(save: false),
                            ),
                          const SizedBox(width: 20),
                          Material(
                            color: _red,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: active ? recorder.stop : _start,
                              child: SizedBox(
                                width: 76,
                                height: 76,
                                child: Icon(
                                  active
                                      ? Icons.stop_rounded
                                      : Icons.mic_rounded,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                          if (active)
                            IconButton.outlined(
                              tooltip: recorder.state == RecorderState.paused
                                  ? 'Reprendre'
                                  : 'Pause',
                              iconSize: 28,
                              icon: Icon(
                                recorder.state == RecorderState.paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              onPressed: recorder.state == RecorderState.paused
                                  ? recorder.resume
                                  : recorder.pause,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        switch (recorder.state) {
                          RecorderState.idle => 'Touchez pour enregistrer',
                          RecorderState.recording => 'Enregistrement en cours',
                          RecorderState.paused => 'En pause',
                        },
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: !recorder.loaded
                  ? const SizedBox.shrink()
                  : recorder.recordings.isEmpty
                  ? Center(
                      child: Text(
                        'Vos enregistrements apparaîtront ici.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      children: [
                        for (final r in recorder.recordings)
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.secondaryContainer,
                              child: Icon(
                                r.path == playingPath
                                    ? Icons.graphic_eq_rounded
                                    : Icons.play_arrow_rounded,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            title: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${formatDuration(r.duration)} · ${formatBytes(r.size)} · ${relativeDate(r.date)}',
                            ),
                            trailing: IconButton(
                              tooltip: 'Options',
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _actions(r),
                            ),
                            onTap: active ? null : () => _play(r),
                            onLongPress: () => _actions(r),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bars for the most recent input levels, newest on the right.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.levels, required this.color});
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final count = (size.width / step).floor();
    final middle = size.height / 2;
    for (var i = 0; i < count; i++) {
      final index = levels.length - count + i;
      final level = index >= 0 ? levels[index] : 0.0;
      final half = 1.5 + level * (middle - 2);
      final x = i * step + step / 2;
      canvas.drawLine(
        Offset(x, middle - half),
        Offset(x, middle + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}
