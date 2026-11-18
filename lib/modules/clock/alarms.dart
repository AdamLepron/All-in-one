import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/notifications.dart';
import '../../core/settings.dart';

/// An alarm clock. [days] holds weekdays (1 Monday … 7 Sunday); empty means
/// it rings once, at the next [hour]:[minute].
class Alarm {
  Alarm({
    this.id = 0,
    required this.hour,
    required this.minute,
    this.label = '',
    Set<int>? days,
    this.enabled = true,
    this.onceAt,
  }) : days = days ?? {};

  int id;
  int hour;
  int minute;
  String label;
  Set<int> days;
  bool enabled;

  /// For a one-time alarm: the moment it was armed for.
  DateTime? onceAt;

  bool get repeats => days.isNotEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'hour': hour,
    'minute': minute,
    'label': label,
    'days': days.toList()..sort(),
    'enabled': enabled,
    'onceAt': onceAt?.millisecondsSinceEpoch,
  };

  static Alarm fromJson(Map<String, dynamic> m) => Alarm(
    id: m['id'] as int,
    hour: (m['hour'] as int).clamp(0, 23),
    minute: (m['minute'] as int).clamp(0, 59),
    label: (m['label'] as String?) ?? '',
    days: {
      for (final d in (m['days'] as List? ?? const []))
        if (d is int && d >= 1 && d <= 7) d,
    },
    enabled: m['enabled'] as bool? ?? true,
    onceAt: m['onceAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['onceAt'] as int),
  );

  Alarm copy() => Alarm(
    id: id,
    hour: hour,
    minute: minute,
    label: label,
    days: {...days},
    enabled: enabled,
    onceAt: onceAt,
  );
}

/// The next moment [a] rings strictly after [now].
DateTime nextRing(Alarm a, DateTime now) {
  DateTime at(int dayOffset) =>
      DateTime(now.year, now.month, now.day + dayOffset, a.hour, a.minute);
  for (var i = 0; i <= 7; i++) {
    final candidate = at(i);
    if (!candidate.isAfter(now)) continue;
    if (a.days.isEmpty || a.days.contains(candidate.weekday)) return candidate;
  }
  return at(8); // unreachable: some day within a week always matches
}

const _dayNames = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];

/// "Une fois", "Tous les jours", "Lun–Ven", "lun, mer, ven".
String daysLabel(Set<int> days) {
  if (days.isEmpty) return 'Une fois';
  if (days.length == 7) return 'Tous les jours';
  final sorted = days.toList()..sort();
  if (sorted.join() == '12345') return 'En semaine';
  if (sorted.join() == '67') return 'Le week-end';
  return sorted.map((d) => _dayNames[d - 1]).join(', ');
}

/// Notification ids of an alarm: one per weekday, or slot 0 otherwise.
int _slotId(int alarmId, int slot) => 300000 + alarmId * 10 + slot;
int snoozeId(int alarmId) => 390000 + alarmId;

/// The user's alarms, stored in the preferences (so backups include them)
/// and armed as system notifications that ring even if the app is closed.
class AlarmStore extends ChangeNotifier {
  AlarmStore(this._settings);
  final AppSettings _settings;

  static const _key = 'alarms';

  List<Alarm> get alarms {
    final raw = _settings.raw(_key);
    if (raw == null) return [];
    try {
      final list = [
        for (final m in jsonDecode(raw) as List)
          Alarm.fromJson(m as Map<String, dynamic>),
      ];
      list.sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );
      return list;
    } on Object {
      return [];
    }
  }

  void _write(List<Alarm> list) {
    _settings.setRaw(_key, jsonEncode([for (final a in list) a.toJson()]));
    notifyListeners();
  }

  /// Adds or updates [alarm] and arms it.
  Future<void> save(Alarm alarm, {DateTime? now}) async {
    final list = alarms;
    if (alarm.id == 0) {
      alarm.id = list.fold<int>(0, (m, a) => a.id > m ? a.id : m) + 1;
      list.add(alarm);
    } else {
      final i = list.indexWhere((a) => a.id == alarm.id);
      i < 0 ? list.add(alarm) : list[i] = alarm;
    }
    await _arm(alarm, now ?? DateTime.now());
    _write(list);
  }

  Future<void> setEnabled(Alarm alarm, bool on, {DateTime? now}) async {
    final a = alarm.copy()..enabled = on;
    await save(a, now: now);
  }

  Future<void> delete(Alarm alarm) async {
    await _disarm(alarm.id);
    _write([
      for (final a in alarms)
        if (a.id != alarm.id) a,
    ]);
  }

  /// Re-arms every alarm (the system may have lost them) and switches off
  /// one-time alarms that rang while the app was closed.
  Future<void> refresh({DateTime? now}) async {
    final time = now ?? DateTime.now();
    final list = alarms;
    var changed = false;
    for (final a in list) {
      final at = a.onceAt;
      if (a.enabled && !a.repeats && at != null && !at.isAfter(time)) {
        a.enabled = false;
        changed = true;
      }
      await _arm(a, time);
    }
    if (changed) _write(list);
  }

  Future<void> _disarm(int id) async {
    for (var slot = 0; slot <= 7; slot++) {
      await Reminders.cancel(_slotId(id, slot));
    }
  }

  Future<void> _arm(Alarm a, DateTime now) async {
    await _disarm(a.id);
    if (!a.enabled) return;
    final payload = 'alarm:${a.id}|${a.label}';
    final title = a.label.isEmpty ? 'Alarme' : a.label;
    final body =
        '${a.hour.toString().padLeft(2, '0')}:${a.minute.toString().padLeft(2, '0')}';
    if (!a.repeats) {
      a.onceAt = nextRing(a, now);
      await Reminders.scheduleAlarm(
        _slotId(a.id, 0),
        title,
        body,
        a.onceAt!,
        payload: payload,
      );
      return;
    }
    a.onceAt = null;
    if (a.days.length == 7) {
      await Reminders.scheduleAlarm(
        _slotId(a.id, 0),
        title,
        body,
        nextRing(a, now),
        payload: payload,
        repeat: AlarmRepeat.daily,
      );
      return;
    }
    for (final day in a.days) {
      final one = Alarm(hour: a.hour, minute: a.minute, days: {day});
      await Reminders.scheduleAlarm(
        _slotId(a.id, day),
        title,
        body,
        nextRing(one, now),
        payload: payload,
        repeat: AlarmRepeat.weekly,
      );
    }
  }
}
