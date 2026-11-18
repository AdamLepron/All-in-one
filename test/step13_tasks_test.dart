import 'package:all_in_one/core/notifications.dart';
import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:all_in_one/modules/tasks/quick_add.dart';
import 'package:all_in_one/modules/tasks/reminder_actions.dart';
import 'package:all_in_one/modules/tasks/tasks_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OrganizerStore store;
  var counter = 0;

  Future<OrganizerStore> fresh([String? name]) async {
    final file = name ?? 'org13_${counter++}.db';
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/$file');
    return OrganizerStore.load(file: file);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async => store = await fresh());

  test('a database made before 1.3 is upgraded', () async {
    const file = 'org13_old.db';
    final path = '${await getDatabasesPath()}/$file';
    await databaseFactory.deleteDatabase(path);
    final old = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
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
      ),
    );
    await old.insert('tasks', {
      'title': 'Vieille',
      'notes': '',
      'has_time': 0,
      'priority': 1,
      'list_name': 'Boîte de réception',
      'done': 0,
      'repeat_rule': 0,
    });
    await old.close();
    final s = await OrganizerStore.load(file: file);
    expect(s.tasks.single.title, 'Vieille');
    expect(s.tasks.single.parentId, isNull);
    expect(s.tasks.single.labels, isEmpty);
  });

  test('steps stay under their task and never show as main tasks', () async {
    final t = Task(title: 'Déménager');
    await store.saveTask(t);
    final a = await store.addSubtask(t, ' Cartons ');
    await store.addSubtask(t, 'Camion');
    expect(await store.addSubtask(t, '   '), isNull);
    expect(await store.addSubtask(a!, 'sous-étape'), isNull); // one level only
    expect(store.subtasks(t).map((s) => s.title), ['Cartons', 'Camion']);
    expect(store.open.map((x) => x.title), ['Déménager']);

    await store.setDone(a, true);
    expect(store.open.map((x) => x.title), ['Déménager']);
    expect(store.completed, isEmpty); // a finished step is not a finished task
    expect(store.subtasks(t).where((s) => s.done), hasLength(1));
  });

  test('deleting a task deletes its steps; clearing done tasks too', () async {
    final t = Task(title: 'A');
    await store.saveTask(t);
    await store.addSubtask(t, 'a1');
    final u = Task(title: 'B');
    await store.saveTask(u);
    await store.addSubtask(u, 'b1');
    await store.deleteTask(t);
    expect(store.tasks.map((x) => x.title), ['B', 'b1']);
    await store.setDone(u, true);
    await store.clearCompleted();
    expect(store.tasks, isEmpty);
  });

  test('a repeating task brings its steps back, undone', () async {
    final t = Task(
      title: 'Ménage',
      due: DateTime(2030, 1, 1),
      repeat: Repeat.weekly,
      labels: ['maison'],
    );
    await store.saveTask(t);
    final step = (await store.addSubtask(t, 'Poussière'))!;
    await store.setDone(step, true);
    await store.setDone(t, true);

    final next = store.open.single;
    expect(next.due, DateTime(2030, 1, 8));
    expect(next.labels, ['maison']);
    final steps = store.subtasks(next);
    expect(steps.map((s) => s.title), ['Poussière']);
    expect(steps.single.done, isFalse);
  });

  test('labels are collected and survive a backup round trip', () async {
    await store.saveTask(Task(title: 'a', labels: ['travail', 'urgent']));
    await store.saveTask(Task(title: 'b', labels: ['Maison']));
    expect(store.labels, ['Maison', 'travail', 'urgent']);
    final data = store.exportData();
    final copy = await fresh();
    await copy.replaceAll(taskRows: data['tasks']!, eventRows: data['events']!);
    expect(copy.tasks.map((t) => t.labels).expand((l) => l).toSet(), {
      'travail',
      'urgent',
      'Maison',
    });
  });

  test('quick add reads #labels and leaves the rest alone', () {
    final now = DateTime(2030, 5, 5, 8);
    final q = parseQuickTask('appeler Paul demain 9h #Travail #urgent!', now);
    expect(q.labels, ['travail']); // "#urgent!" is not a clean word
    expect(q.title, 'appeler Paul #urgent!');
    final r = parseQuickTask('acheter du lait #courses #maison #courses', now);
    expect(r.labels, ['courses', 'maison']);
    expect(r.title, 'acheter du lait');
    expect(parseQuickTask('rien', now).labels, isEmpty);
    expect(parseQuickTask('à #3 heures', now).labels, ['3']);
  });

  test('reminder buttons: done completes, snooze moves one hour', () async {
    final t = Task(
      title: 'Médicament',
      due: DateTime(2030, 1, 1, 8),
      hasTime: true,
    );
    await store.saveTask(t);
    final now = DateTime(2030, 1, 1, 8, 5);

    await handleReminderAction(
      store,
      Reminders.taskSnooze,
      'task:${t.id}',
      now: now,
    );
    expect(store.tasks.single.due, DateTime(2030, 1, 1, 9, 5));
    expect(store.tasks.single.done, isFalse);

    // Ignored: plain tap, unknown task, foreign payload, bad id.
    await handleReminderAction(store, null, 'task:${t.id}');
    await handleReminderAction(store, Reminders.taskDone, 'task:9999');
    await handleReminderAction(store, Reminders.taskDone, 'event:${t.id}');
    await handleReminderAction(store, Reminders.taskDone, 'task:abc');
    await handleReminderAction(store, Reminders.taskDone, null);
    expect(store.tasks.single.done, isFalse);

    await handleReminderAction(store, Reminders.taskDone, 'task:${t.id}');
    expect(store.tasks.single.done, isTrue);
    // Pressing again on a finished task changes nothing.
    await handleReminderAction(
      store,
      Reminders.taskSnooze,
      'task:${t.id}',
      now: now,
    );
    expect(store.tasks.single.due, DateTime(2030, 1, 1, 9, 5));
  });

  testWidgets('tasks page: #label in the field, filter, steps counter', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await tester.runAsync(() async {
      final t = Task(title: 'Projet', due: DateTime.now(), labels: ['travail']);
      await store.saveTask(t);
      await store.addSubtask(t, 'Plan');
      final s2 = await store.addSubtask(t, 'Budget');
      await store.setDone(s2!, true);
      await store.saveTask(
        Task(title: 'Yoga', due: DateTime.now(), labels: ['sport']),
      );
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ],
        child: const MaterialApp(home: TasksPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Projet'), findsOneWidget);
    expect(find.text('Plan'), findsNothing); // steps are not listed alone
    expect(find.textContaining('1/2 étapes'), findsOneWidget);
    expect(find.textContaining('#travail'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, 'sport'));
    await tester.pump();
    expect(find.text('Yoga'), findsOneWidget);
    expect(find.text('Projet'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, 'sport'));
    await tester.pump();
    expect(find.text('Projet'), findsOneWidget);

    // Typing a task with a label shows it before it is created.
    await tester.enterText(find.byType(TextField), 'Ranger #maison');
    await tester.pump();
    expect(find.text('maison'), findsOneWidget);
  });
}
