import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/platform.dart';

class Recording {
  Recording(this.path, this.duration, this.size, this.date);
  final String path;
  final Duration duration;
  final int size;
  final DateTime date;

  String get name => p.basenameWithoutExtension(path);
}

enum RecorderState { idle, recording, paused }

/// Records from the microphone and keeps the list of saved recordings.
///
/// [directory] is where files are stored; by default a private folder of
/// the app.
class RecorderController extends ChangeNotifier {
  RecorderController({Future<String> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static Future<String> _defaultDirectory() async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'recordings');

  final Future<String> Function() _directory;
  AudioRecorder? _recorder;
  StreamSubscription<Amplitude>? _levels;
  final _clock = Stopwatch();
  String? _currentPath;

  RecorderState state = RecorderState.idle;
  bool lossless = false;
  List<Recording> recordings = [];
  bool loaded = false;

  /// Recent input levels from 0 to 1, oldest first.
  final List<double> waveform = [];

  Duration get elapsed => _clock.elapsed;

  /// Folder holding every recording.
  Future<String> get directory => _dir();

  Future<String> _dir() async {
    final dir = await _directory();
    await Directory(dir).create(recursive: true);
    return dir;
  }

  Future<Map<String, int>> _readIndex(String dir) async {
    try {
      final map = jsonDecode(
        await File(p.join(dir, 'index.json')).readAsString(),
      );
      return (map as Map<String, dynamic>).cast<String, int>();
    } on Object {
      return {};
    }
  }

  Future<void> _writeIndex(String dir, Map<String, int> index) =>
      File(p.join(dir, 'index.json')).writeAsString(jsonEncode(index));

  /// Reads the saved recordings, most recent first.
  Future<void> load() async {
    final dir = await _dir();
    final index = await _readIndex(dir);
    final list = <Recording>[];
    await for (final entity in Directory(dir).list()) {
      if (entity is! File || p.extension(entity.path) == '.json') continue;
      final stat = await entity.stat();
      list.add(
        Recording(
          entity.path,
          Duration(milliseconds: index[p.basename(entity.path)] ?? 0),
          stat.size,
          stat.modified,
        ),
      );
    }
    recordings = list..sort((a, b) => b.date.compareTo(a.date));
    loaded = true;
    notifyListeners();
  }

  /// Returns false when microphone access is refused.
  Future<bool> start() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) return false;
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'Enregistrement ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}h${two(now.minute)}m${two(now.second)}';
    _currentPath = p.join(await _dir(), '$name.${lossless ? 'wav' : 'm4a'}');
    await recorder.start(
      RecordConfig(
        encoder: lossless ? AudioEncoder.wav : AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _currentPath!,
    );
    waveform.clear();
    _levels = recorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((a) {
          // dBFS from -50 (quiet) to 0 (loudest) mapped to 0–1.
          waveform.add(((a.current + 50) / 50).clamp(0.0, 1.0));
          if (waveform.length > 400) waveform.removeAt(0);
          notifyListeners();
        });
    _clock
      ..reset()
      ..start();
    state = RecorderState.recording;
    unawaited(MediaChannel.keepScreenOn(true));
    notifyListeners();
    return true;
  }

  Future<void> pause() async {
    await _recorder?.pause();
    _clock.stop();
    state = RecorderState.paused;
    notifyListeners();
  }

  Future<void> resume() async {
    await _recorder?.resume();
    _clock.start();
    state = RecorderState.recording;
    notifyListeners();
  }

  /// Ends the recording; with [save] false the file is discarded.
  Future<void> stop({bool save = true}) async {
    if (state == RecorderState.idle) return;
    _clock.stop();
    await _levels?.cancel();
    await _recorder?.stop();
    final path = _currentPath;
    state = RecorderState.idle;
    unawaited(MediaChannel.keepScreenOn(false));
    if (path != null) {
      if (save) {
        final dir = p.dirname(path);
        final index = await _readIndex(dir);
        index[p.basename(path)] = _clock.elapsedMilliseconds;
        await _writeIndex(dir, index);
      } else if (await File(path).exists()) {
        await File(path).delete();
      }
    }
    _currentPath = null;
    await load();
  }

  Future<void> delete(Recording r) async {
    await File(r.path).delete();
    final dir = p.dirname(r.path);
    final index = await _readIndex(dir)
      ..remove(p.basename(r.path));
    await _writeIndex(dir, index);
    await load();
  }

  /// Returns false when another recording already has that name.
  Future<bool> rename(Recording r, String name) async {
    final dir = p.dirname(r.path);
    final target = p.join(dir, '$name${p.extension(r.path)}');
    if (target == r.path) return true;
    if (await File(target).exists()) return false;
    await File(r.path).rename(target);
    final index = await _readIndex(dir);
    final duration = index.remove(p.basename(r.path));
    if (duration != null) index[p.basename(target)] = duration;
    await _writeIndex(dir, index);
    await load();
    return true;
  }

  void setLossless(bool value) {
    lossless = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _levels?.cancel();
    _recorder?.dispose();
    super.dispose();
  }
}
