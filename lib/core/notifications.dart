import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'platform.dart';

/// How an alarm repeats.
enum AlarmRepeat { none, daily, weekly }

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
      await _useDeviceTimeZone();
    } on MissingPluginException {
      _ready = false;
    } on PlatformException {
      _ready = false;
    }
  }

  /// Repeating alarms follow the device's time zone, daylight saving included.
  static Future<void> _useDeviceTimeZone() async {
    try {
      tzdata.initializeTimeZones();
      final name = await MediaChannel.timeZone();
      if (name != null) tz.setLocalLocation(tz.getLocation(name));
    } on Object {
      // Unknown zone: times stay in UTC, which only affects repeats.
    }
  }

  static const alarmStop = 'alarm_stop';
  static const alarmSnooze = 'alarm_snooze';

  /// Rings at [when] with a loud, insistent notification. A [repeat]
  /// repeats it every day or every week at the same time.
  static Future<void> scheduleAlarm(
    int id,
    String title,
    String? body,
    DateTime when, {
    String? payload,
    AlarmRepeat repeat = AlarmRepeat.none,
    bool buttons = true,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
      if (repeat == AlarmRepeat.none && !when.isAfter(DateTime.now())) return;
      final exact = await _android?.canScheduleExactNotifications() ?? false;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'alarms',
          'Alarmes et minuteurs',
          channelDescription: 'Sonne à l\'heure choisie, même app fermée',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
          additionalFlags: Int32List.fromList([4]), // FLAG_INSISTENT
          actions: buttons
              ? const [
                  AndroidNotificationAction(alarmStop, 'Arrêter'),
                  AndroidNotificationAction(alarmSnooze, 'Répéter 10 min'),
                ]
              : null,
        ),
      );
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: details,
        payload: payload,
        matchDateTimeComponents: switch (repeat) {
          AlarmRepeat.none => null,
          AlarmRepeat.daily => DateTimeComponents.time,
          AlarmRepeat.weekly => DateTimeComponents.dayOfWeekAndTime,
        },
        androidScheduleMode: exact
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException {
      // Refused by the system: nothing else to do.
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
