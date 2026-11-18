import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/notifications.dart';
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
    // Rings even if the system stops the app in the meantime.
    Reminders.scheduleAlarm(
      _mainTimerId,
      'Minuteur terminé',
      formatCountdown(timerTotal),
      _endsAt!,
      buttons: false,
    );
    notifyListeners();
  }

  void pauseTimer() {
    _pausedRemaining = remaining;
    _endsAt = null;
    _alarm?.cancel();
    Reminders.cancel(_mainTimerId);
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
    // The app is alive and rings itself: the system notification is not needed.
    Reminders.cancel(_mainTimerId);
    _syncRing();
    notifyListeners();
  }

  /// Stops the countdown or the alarm sound and returns to the setup view.
  void resetTimer() {
    _alarm?.cancel();
    _endsAt = null;
    _pausedRemaining = null;
    ringing = false;
    Reminders.cancel(_mainTimerId);
    _syncRing();
    notifyListeners();
  }

  static const _mainTimerId = 399999;

  void _changed() => notifyListeners();

  // ---- More timers ----

  /// Timers started next to the main countdown, each with its own name.
  final extras = <CountdownTimer>[];
  int _nextExtra = 1;

  /// Starts a new timer of [total] right away.
  CountdownTimer addExtra(Duration total, {String label = ''}) {
    final t = CountdownTimer._(_nextExtra++, total, label, this);
    extras.add(t);
    t._run(total);
    notifyListeners();
    return t;
  }

  void removeExtra(CountdownTimer t) {
    t._stop();
    extras.remove(t);
    _syncRing();
    notifyListeners();
  }

  /// The alarm sound plays while any timer is ringing.
  bool _soundOn = false;
  void _syncRing() {
    final any = ringing || extras.any((t) => t.ringing);
    if (any == _soundOn) return;
    _soundOn = any;
    MediaChannel.ring(any);
  }

  @override
  void dispose() {
    _alarm?.cancel();
    for (final t in extras) {
      t._stop();
    }
    super.dispose();
  }
}

/// One of the extra timers.
class CountdownTimer {
  CountdownTimer._(this.id, this.total, this.label, this._clock);

  final int id;
  Duration total;
  final String label;
  final ClockController _clock;

  DateTime? _endsAt;
  Duration? _paused;
  Timer? _timer;
  bool ringing = false;

  bool get running => _endsAt != null;
  bool get paused => _paused != null;

  Duration get remaining {
    final end = _endsAt;
    if (end != null) {
      final left = end.difference(DateTime.now());
      return left.isNegative ? Duration.zero : left;
    }
    return _paused ?? total;
  }

  int get _notificationId => 410000 + id;

  void _run(Duration left) {
    _paused = null;
    ringing = false;
    _endsAt = DateTime.now().add(left);
    _timer?.cancel();
    _timer = Timer(left, () {
      _endsAt = null;
      ringing = true;
      Reminders.cancel(_notificationId);
      _clock._syncRing();
      _clock._changed();
    });
    Reminders.scheduleAlarm(
      _notificationId,
      label.isEmpty ? 'Minuteur terminé' : label,
      formatCountdown(total),
      _endsAt!,
      buttons: false,
    );
  }

  void _stop() {
    _timer?.cancel();
    Reminders.cancel(_notificationId);
  }

  void pause() {
    if (!running) return;
    _paused = remaining;
    _endsAt = null;
    _stop();
    _clock._changed();
  }

  void resume() {
    if (!paused) return;
    _run(_paused!);
    _clock._changed();
  }

  void addMinute() {
    if (!running) return;
    total += const Duration(minutes: 1);
    _run(remaining + const Duration(minutes: 1));
    _clock._changed();
  }

  /// Starts again from the full duration.
  void restart() {
    _run(total);
    _clock._syncRing();
    _clock._changed();
  }

  /// Silences the sound of a finished timer.
  void dismiss() {
    ringing = false;
    _clock._syncRing();
    _clock._changed();
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
