import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/platform.dart';

/// Stopwatch and countdown that keep running while the user visits other
/// screens of the app.
class ClockController extends ChangeNotifier {
  // ---- Stopwatch ----
  final _watch = Stopwatch();

  /// Total elapsed time at each lap.
  final laps = <Duration>[];

  Duration get elapsed => _watch.elapsed;
  bool get watchRunning => _watch.isRunning;

  void toggleWatch() {
    _watch.isRunning ? _watch.stop() : _watch.start();
    notifyListeners();
  }

  void lap() {
    laps.insert(0, _watch.elapsed);
    notifyListeners();
  }

  void resetWatch() {
    _watch
      ..stop()
      ..reset();
    laps.clear();
    notifyListeners();
  }

  // ---- Countdown ----
  Duration timerTotal = const Duration(minutes: 5);
  DateTime? _endsAt;
  Duration? _pausedRemaining;
  Timer? _alarm;
  bool ringing = false;

  bool get timerRunning => _endsAt != null;
  bool get timerPaused => _pausedRemaining != null;
  bool get timerIdle => !timerRunning && !timerPaused && !ringing;

  Duration get remaining {
    final end = _endsAt;
    if (end != null) {
      final left = end.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }
    return _pausedRemaining ?? timerTotal;
  }

  void setTimer(Duration total) {
    if (!timerIdle || total <= Duration.zero) return;
    timerTotal = total;
    notifyListeners();
  }

  void startTimer() => _run(_pausedRemaining ?? timerTotal);

  void _run(Duration left) {
    _pausedRemaining = null;
    _endsAt = DateTime.now().add(left);
    _alarm?.cancel();
    _alarm = Timer(left, _finish);
    notifyListeners();
  }

  void pauseTimer() {
    _pausedRemaining = remaining;
    _endsAt = null;
    _alarm?.cancel();
    notifyListeners();
  }

  void addMinute() {
    if (timerRunning) {
      timerTotal += const Duration(minutes: 1);
      _run(remaining + const Duration(minutes: 1));
    }
  }

  void _finish() {
    _endsAt = null;
    ringing = true;
    MediaChannel.ring(true);
    notifyListeners();
  }

  /// Stops the countdown or the alarm sound and returns to the setup view.
  void resetTimer() {
    _alarm?.cancel();
    _endsAt = null;
    _pausedRemaining = null;
    if (ringing) MediaChannel.ring(false);
    ringing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _alarm?.cancel();
    super.dispose();
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "05:00", "1:05:00" — rounded up so a countdown never shows 00:00 early.
String formatCountdown(Duration d) {
  final seconds = (d.inMilliseconds / 1000).ceil();
  final h = seconds ~/ 3600;
  final m = seconds % 3600 ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// "01:23,45" — minutes, seconds and hundredths.
String formatStopwatch(Duration d) {
  final cs = d.inMilliseconds ~/ 10;
  final h = cs ~/ 360000;
  final rest =
      '${_two(cs % 360000 ~/ 6000)}:${_two(cs % 6000 ~/ 100)},${_two(cs % 100)}';
  return h > 0 ? '$h:$rest' : rest;
}
