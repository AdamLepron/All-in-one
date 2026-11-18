import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/notifications.dart';
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

/// Runs when a reminder's button is pressed while the app is closed. It runs
/// in its own isolate, so it opens the database itself.
@pragma('vm:entry-point')
Future<void> reminderBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  await Reminders.init();
  final store = await OrganizerStore.load();
  await handleReminderAction(store, response.actionId, response.payload);
}
