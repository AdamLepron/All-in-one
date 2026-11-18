import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Schedules reminder notifications. Every call is a no-op when the
/// platform side is missing (tests).
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Rappels',
      channelDescription: 'Rappels des tâches et des événements',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// Called when a button of a reminder is pressed while the app runs.
  static void Function(String? actionId, String? payload)? onAction;

  /// [background] handles button presses while the app is closed; it must
  /// be a top-level function.
  static Future<void> init({
    DidReceiveBackgroundNotificationResponseCallback? background,
  }) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (r) =>
            onAction?.call(r.actionId, r.payload),
        onDidReceiveBackgroundNotificationResponse: background,
      );
      _ready = true;
    } on MissingPluginException {
      _ready = false;
    } on PlatformException {
      _ready = false;
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Asks for the notification permission (Android 13+). Call it when the
  /// user first sets a reminder, not at startup.
  static Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _android?.requestNotificationsPermission();
    } on PlatformException {
      // Left as is: reminders simply stay silent.
    }
  }

  /// Buttons shown under a task's reminder.
  static const taskDone = 'done';
  static const taskSnooze = 'snooze';

  static const _taskDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Rappels',
      channelDescription: 'Rappels des tâches et des événements',
      importance: Importance.high,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction(taskDone, 'Terminé'),
        AndroidNotificationAction(taskSnooze, 'Reporter 1 h'),
      ],
    ),
  );

  /// Shows [title] at [when]; a past time cancels the reminder instead.
  /// With a [taskId], the notification offers "Terminé" and "Reporter 1 h".
  static Future<void> schedule(
    int id,
    String title,
    String? body,
    DateTime when, {
    int? taskId,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
      if (!when.isAfter(DateTime.now())) return;
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: taskId == null ? _details : _taskDetails,
        payload: taskId == null ? null : 'task:$taskId',
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException {
      // Scheduling refused by the system: nothing else to do.
    }
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } on PlatformException {
      // Already gone.
    }
  }
}
