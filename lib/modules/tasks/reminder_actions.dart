import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/notifications.dart';
import '../clock/alarms.dart';
import 'organizer_store.dart';

/// Applies a press on a task reminder's button: "Terminé" completes the
/// task, "Reporter 1 h" moves its reminder one hour ahead. A plain tap
/// (no action) does nothing here: the app simply opens.
Future<void> handleReminderAction(
  OrganizerStore store,
  String? actionId,
  String? payload, {
  DateTime? now,
}) async {
  if (payload != null && payload.startsWith('alarm:')) {
    await handleAlarmAction(actionId, payload, now: now);
    return;
  }
  if (payload == null || !payload.startsWith('task:')) return;
  final id = int.tryParse(payload.substring(5));
  if (id == null) return;
  final task = store.tasks.where((t) => t.id == id).firstOrNull;
  if (task == null || task.done) return;
  switch (actionId) {
    case Reminders.taskDone:
      await store.setDone(task, true);
    case Reminders.taskSnooze:
      task
        ..due = (now ?? DateTime.now()).add(const Duration(hours: 1))
        ..hasTime = true;
      await store.saveTask(task);
  }
}

/// "Répéter 10 min" on a ringing alarm rings it again ten minutes later.
/// The payload looks like alarm:ID|label.
Future<void> handleAlarmAction(
  String? actionId,
  String payload, {
  DateTime? now,
}) async {
  if (actionId != Reminders.alarmSnooze) return;
  final rest = payload.substring(6);
  final bar = rest.indexOf('|');
  final id = int.tryParse(bar < 0 ? rest : rest.substring(0, bar));
  if (id == null) return;
  final label = bar < 0 ? '' : rest.substring(bar + 1);
  final when = (now ?? DateTime.now()).add(const Duration(minutes: 10));
  await Reminders.scheduleAlarm(
    snoozeId(id),
    label.isEmpty ? 'Alarme' : label,
    'Répétée',
    when,
    payload: payload,
  );
}

/// Runs when a reminder's button is pressed while the app is closed. It runs
/// in its own isolate, so it opens the database itself.
@pragma('vm:entry-point')
Future<void> reminderBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await Reminders.init();
  final store = await OrganizerStore.load();
  await handleReminderAction(store, response.actionId, response.payload);
}
