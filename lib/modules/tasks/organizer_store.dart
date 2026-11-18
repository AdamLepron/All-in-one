import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/notifications.dart';

enum Repeat {
  none('Jamais'),
  daily('Tous les jours'),
  weekly('Toutes les semaines'),
  monthly('Tous les mois'),
  yearly('Tous les ans');

  const Repeat(this.label);
  final String label;

  /// The occurrence following [from].
  DateTime next(DateTime from) => switch (this) {
    none => from,
    daily => DateTime(
      from.year,
      from.month,
      from.day + 1,
      from.hour,
      from.minute,
    ),
    weekly => DateTime(
      from.year,
      from.month,
      from.day + 7,
      from.hour,
      from.minute,
    ),
    monthly => DateTime(
      from.year,
      from.month + 1,
      from.day,
      from.hour,
      from.minute,
    ),
    yearly => DateTime(
      from.year + 1,
      from.month,
      from.day,
      from.hour,
      from.minute,
    ),
  };
}

class Task {
  Task({
    this.id,
    required this.title,
    this.notes = '',
    this.due,
    this.hasTime = false,
    this.priority = 0,
    this.list = 'Boîte de réception',
    this.done = false,
    this.doneAt,
    this.repeat = Repeat.none,
  });

  int? id;
  String title;
  String notes;
  DateTime? due;

  /// False when only the day matters.
  bool hasTime;
  int priority;
  String list;
  bool done;
  DateTime? doneAt;
  Repeat repeat;

  bool isOverdue(DateTime now) {
    final d = due;
    if (d == null || done) return false;
    return hasTime
        ? d.isBefore(now)
        : d.isBefore(DateTime(now.year, now.month, now.day));
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'notes': notes,
    'due': due?.millisecondsSinceEpoch,
    'has_time': hasTime ? 1 : 0,
    'priority': priority,
    'list_name': list,
    'done': done ? 1 : 0,
    'done_at': doneAt?.millisecondsSinceEpoch,
    'repeat_rule': repeat.index,
  };

  static Task fromMap(Map<String, Object?> m) => Task(
    id: m['id'] as int,
    title: m['title'] as String,
    notes: m['notes'] as String,
    due: m['due'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['due'] as int),
    hasTime: m['has_time'] == 1,
    priority: m['priority'] as int,
    list: m['list_name'] as String,
    done: m['done'] == 1,
    doneAt: m['done_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['done_at'] as int),
    repeat: Repeat.values[m['repeat_rule'] as int],
  );
}

class Event {
  Event({
    this.id,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location = '',
    this.notes = '',
    this.color = 0,
    this.repeat = Repeat.none,
    this.reminder,
    this.external = false,
    this.calendar = '',
    this.externalColor,
  });

  int? id;
  String title;
  DateTime start;
  DateTime end;
  bool allDay;
  String location;
  String notes;

  /// Index into the event colour palette.
  int color;
  Repeat repeat;

  /// Minutes before the start, or null for no reminder.
  int? reminder;

  /// True for events read from the phone's calendars; these are read-only.
  final bool external;
  final String calendar;
  final int? externalColor;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'start_at': start.millisecondsSinceEpoch,
    'end_at': end.millisecondsSinceEpoch,
    'all_day': allDay ? 1 : 0,
    'location': location,
    'notes': notes,
    'color': color,
    'repeat_rule': repeat.index,
    'reminder': reminder,
  };

  static Event fromMap(Map<String, Object?> m) => Event(
    id: m['id'] as int,
    title: m['title'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(m['start_at'] as int),
    end: DateTime.fromMillisecondsSinceEpoch(m['end_at'] as int),
    allDay: m['all_day'] == 1,
    location: m['location'] as String,
    notes: m['notes'] as String,
    color: m['color'] as int,
    repeat: Repeat.values[m['repeat_rule'] as int],
    reminder: m['reminder'] as int?,
  );

  /// This event moved to another occurrence starting at [at].
  Event occurrence(DateTime at) => Event(
    id: id,
    title: title,
    start: at,
    end: at.add(end.difference(start)),
    allDay: allDay,
    location: location,
    notes: notes,
    color: color,
    repeat: repeat,
    reminder: reminder,
  );
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Tasks and calendar events, stored in SQLite and mirrored in memory.
class OrganizerStore extends ChangeNotifier {
  OrganizerStore._(this._db);

  final Database _db;
  List<Task> tasks = [];
  List<Event> events = [];

  /// [file] lets tests use separate databases.
  static Future<OrganizerStore> load({String file = 'organizer.db'}) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), file),
      version: 1,
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, notes TEXT NOT NULL, due INTEGER, '
          'has_time INTEGER NOT NULL, priority INTEGER NOT NULL, '
          'list_name TEXT NOT NULL, done INTEGER NOT NULL, done_at INTEGER, '
          'repeat_rule INTEGER NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE events(id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'title TEXT NOT NULL, start_at INTEGER NOT NULL, end_at INTEGER NOT NULL, '
          'all_day INTEGER NOT NULL, location TEXT NOT NULL, '
          'notes TEXT NOT NULL, color INTEGER NOT NULL, '
          'repeat_rule INTEGER NOT NULL, reminder INTEGER)',
        );
      },
    );
    final store = OrganizerStore._(db);
    await store._reload();
    return store;
  }

  Future<void> _reload() async {
    tasks = (await _db.query('tasks')).map(Task.fromMap).toList();
    events = (await _db.query('events')).map(Event.fromMap).toList();
    notifyListeners();
  }

  // ---- Tasks ----

  List<String> get lists {
    final names = {
      'Boîte de réception',
      for (final t in tasks) t.list,
    }.toList();
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// Open tasks ordered by date, then priority; undated ones come last.
  List<Task> get open => tasks.where((t) => !t.done).toList()..sort(_byDue);

  List<Task> get completed => tasks.where((t) => t.done).toList()
    ..sort(
      (a, b) => (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)),
    );

  static int _byDue(Task a, Task b) {
    final ad = a.due, bd = b.due;
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    final byDate = ad == null ? 0 : ad.compareTo(bd!);
    return byDate != 0 ? byDate : b.priority.compareTo(a.priority);
  }

  /// Tasks due on [day] or, with [overdue], also earlier ones still open.
  List<Task> tasksOn(DateTime day, {bool overdue = false}) => open.where((t) {
    final d = t.due;
    if (d == null) return false;
    return dayOf(d) == dayOf(day) || (overdue && d.isBefore(dayOf(day)));
  }).toList();

  int _taskReminderId(Task t) => 100000 + t.id!;

  Future<void> saveTask(Task task) async {
    if (task.id == null) {
      task.id = await _db.insert('tasks', task.toMap()..remove('id'));
    } else {
      await _db.update(
        'tasks',
        task.toMap(),
        where: 'id = ?',
        whereArgs: [task.id],
      );
    }
    if (task.hasTime && !task.done && task.due != null) {
      await Reminders.schedule(
        _taskReminderId(task),
        task.title,
        'Tâche à faire',
        task.due!,
      );
    } else {
      await Reminders.cancel(_taskReminderId(task));
    }
    await _reload();
  }

  /// Marks [task] done or not. Completing a repeating task schedules its
  /// next occurrence.
  Future<void> setDone(Task task, bool done) async {
    task
      ..done = done
      ..doneAt = done ? DateTime.now() : null;
    await saveTask(task);
    if (done && task.repeat != Repeat.none && task.due != null) {
      await saveTask(
        Task(
          title: task.title,
          notes: task.notes,
          due: task.repeat.next(task.due!),
          hasTime: task.hasTime,
          priority: task.priority,
          list: task.list,
          repeat: task.repeat,
        ),
      );
    }
  }

  Future<void> deleteTask(Task task) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [task.id]);
    await Reminders.cancel(_taskReminderId(task));
    await _reload();
  }

  Future<void> clearCompleted() async {
    await _db.delete('tasks', where: 'done = 1');
    await _reload();
  }

  // ---- Backup ----

  /// Every task and event as plain maps, for backups.
  Map<String, List<Map<String, Object?>>> exportData() => {
    'tasks': [for (final t in tasks) t.toMap()],
    'events': [for (final e in events) e.toMap()],
  };

  /// Replaces all tasks and events (as given by [exportData]) and arms
  /// the reminders again.
  Future<void> replaceAll({
    required List<Map<String, Object?>> taskRows,
    required List<Map<String, Object?>> eventRows,
  }) async {
    final newTasks = [
      for (final r in taskRows) Task.fromMap(r),
    ]; // validates first
    final newEvents = [for (final r in eventRows) Event.fromMap(r)];
    for (final t in tasks) {
      await Reminders.cancel(_taskReminderId(t));
    }
    for (final e in events) {
      await Reminders.cancel(_eventReminderId(e));
    }
    await _db.transaction((txn) async {
      await txn.delete('tasks');
      await txn.delete('events');
      for (final t in newTasks) {
        await txn.insert('tasks', t.toMap());
      }
      for (final e in newEvents) {
        await txn.insert('events', e.toMap());
      }
    });
    await _reload();
    for (final t in tasks) {
      if (t.hasTime && !t.done && t.due != null) {
        await Reminders.schedule(
          _taskReminderId(t),
          t.title,
          'Tâche à faire',
          t.due!,
        );
      }
    }
    for (final e in events) {
      await _scheduleEvent(e);
    }
  }

  // ---- Events ----

  /// Occurrences of every event that touch [from, to), repeats expanded,
  /// ordered by start.
  List<Event> eventsBetween(DateTime from, DateTime to) {
    final result = <Event>[];
    for (final e in events) {
      if (e.repeat == Repeat.none) {
        if (e.start.isBefore(to) && e.end.isAfter(from)) result.add(e);
        continue;
      }
      final length = e.end.difference(e.start);
      var at = e.start;
      // Bounded so a corrupt record can never loop forever.
      for (var i = 0; i < 5000 && at.isBefore(to); i++) {
        if (at.add(length).isAfter(from)) {
          result.add(i == 0 ? e : e.occurrence(at));
        }
        at = e.repeat.next(at);
      }
    }
    return result..sort((a, b) => a.start.compareTo(b.start));
  }

  int _eventReminderId(Event e) => 200000 + e.id!;

  /// Schedules the reminder of the next occurrence still ahead.
  Future<void> _scheduleEvent(Event e) async {
    final minutes = e.reminder;
    if (minutes == null) return Reminders.cancel(_eventReminderId(e));
    final now = DateTime.now();
    var at = e.start;
    for (var i = 0; i < 5000; i++) {
      if (at.subtract(Duration(minutes: minutes)).isAfter(now)) break;
      if (e.repeat == Repeat.none) return Reminders.cancel(_eventReminderId(e));
      at = e.repeat.next(at);
    }
    await Reminders.schedule(
      _eventReminderId(e),
      e.title,
      minutes == 0 ? 'Maintenant' : 'Dans $minutes min',
      at.subtract(Duration(minutes: minutes)),
    );
  }

  Future<void> saveEvent(Event event) async {
    if (event.id == null) {
      event.id = await _db.insert('events', event.toMap()..remove('id'));
    } else {
      await _db.update(
        'events',
        event.toMap(),
        where: 'id = ?',
        whereArgs: [event.id],
      );
    }
    await _scheduleEvent(event);
    await _reload();
  }

  Future<void> deleteEvent(Event event) async {
    await _db.delete('events', where: 'id = ?', whereArgs: [event.id]);
    await Reminders.cancel(_eventReminderId(event));
    await _reload();
  }

  /// Re-arms reminders, e.g. for repeating events whose last occurrence
  /// has passed. Called at startup.
  Future<void> refreshReminders() async {
    for (final e in events) {
      if (e.repeat != Repeat.none && e.reminder != null) {
        await _scheduleEvent(e);
      }
    }
  }
}
