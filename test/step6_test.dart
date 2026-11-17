import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:all_in_one/modules/tasks/quick_add.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Monday 16 November 2026, 10:00.
  final now = DateTime(2026, 11, 16, 10);

  group('quick add', () {
    QuickTask parse(String s) => parseQuickTask(s, now);

    test('plain title', () {
      final t = parse('Acheter du pain');
      expect(t.title, 'Acheter du pain');
      expect(t.due, isNull);
      expect(t.priority, 0);
    });

    test('relative days and times', () {
      var t = parse('appeler Paul demain 9h');
      expect(t.title, 'appeler Paul');
      expect(t.due, DateTime(2026, 11, 17, 9));
      expect(t.hasTime, true);

      t = parse("Rendre le dossier aujourd'hui");
      expect(t.due, DateTime(2026, 11, 16));
      expect(t.hasTime, false);

      t = parse('Dentiste après-demain à 14h30');
      expect(t.title, 'Dentiste');
      expect(t.due, DateTime(2026, 11, 18, 14, 30));

      t = parse('Révision dans 2 semaines');
      expect(t.due, DateTime(2026, 11, 30));
      expect(t.title, 'Révision');

      t = parse('Cinéma ce soir');
      expect(t.due, DateTime(2026, 11, 16, 19));
    });

    test('weekdays', () {
      expect(parse('Sport vendredi').due, DateTime(2026, 11, 20));
      // Said on a Monday, "lundi" is next week.
      expect(parse('Réunion lundi 10h').due, DateTime(2026, 11, 23, 10));
      expect(parse('Marché dimanche prochain').title, 'Marché');
    });

    test('explicit dates', () {
      expect(
        parse('Impôts le 12 mars').due,
        DateTime(2027, 3, 12),
      ); // already passed
      expect(parse('Anniversaire 3 décembre').due, DateTime(2026, 12, 3));
      expect(parse('Contrôle 24/12 à 8h').due, DateTime(2026, 12, 24, 8));
      expect(parse('Rapport 1er janvier 2028').due, DateTime(2028, 1, 1));
    });

    test('a time alone is today or tomorrow', () {
      expect(parse('Appel 15h').due, DateTime(2026, 11, 16, 15));
      expect(parse('Appel 8h').due, DateTime(2026, 11, 17, 8)); // 8h has passed
      expect(parse('Déjeuner à midi').due, DateTime(2026, 11, 16, 12));
    });

    test('priority and words that only look like dates', () {
      final t = parse('Payer le loyer demain urgent');
      expect(t.priority, 3);
      expect(t.title, 'Payer le loyer');
      expect(parse('Dossier important').priority, 2);
      // "mars" inside a word and a bare number are left alone.
      expect(parse('Lire Marseille 2030').title, 'Lire Marseille 2030');
      expect(parse('Lire Marseille 2030').due, isNull);
      expect(parse('Acheter 12 œufs').due, isNull);
    });
  });

  group('organizer store', () {
    late OrganizerStore store;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/organizer_unit.db',
      );
      store = await OrganizerStore.load(file: 'organizer_unit.db');
    });

    test('tasks: ordering, overdue, repeat on completion', () async {
      final today = dayOf(DateTime.now());
      await store.saveTask(Task(title: 'Sans date'));
      await store.saveTask(
        Task(title: 'Demain', due: today.add(const Duration(days: 1))),
      );
      await store.saveTask(
        Task(
          title: 'Hier',
          due: today.subtract(const Duration(days: 1)),
          priority: 3,
        ),
      );
      expect(store.open.map((t) => t.title), ['Hier', 'Demain', 'Sans date']);
      expect(store.open.first.isOverdue(DateTime.now()), true);
      expect(store.tasksOn(today), isEmpty);
      expect(store.tasksOn(today, overdue: true).single.title, 'Hier');

      final daily = Task(title: 'Arroser', due: today, repeat: Repeat.daily);
      await store.saveTask(daily);
      await store.setDone(daily, true);
      expect(store.completed.single.title, 'Arroser');
      final next = store.open.firstWhere((t) => t.title == 'Arroser');
      expect(next.due, today.add(const Duration(days: 1)));

      await store.deleteTask(next);
      await store.clearCompleted();
      expect(store.tasks.where((t) => t.title == 'Arroser'), isEmpty);
    });

    test('events: range query and repetition', () async {
      await store.saveEvent(
        Event(
          title: 'Point hebdo',
          start: DateTime(2026, 11, 2, 10),
          end: DateTime(2026, 11, 2, 11),
          repeat: Repeat.weekly,
        ),
      );
      await store.saveEvent(
        Event(
          title: 'Séminaire',
          start: DateTime(2026, 11, 18),
          end: DateTime(2026, 11, 21),
          allDay: true,
        ),
      );
      final november = store.eventsBetween(
        DateTime(2026, 11),
        DateTime(2026, 12),
      );
      expect(november.where((e) => e.title == 'Point hebdo').length, 5);
      expect(
        november.where((e) => e.title == 'Point hebdo').map((e) => e.start.day),
        [2, 9, 16, 23, 30],
      );
      // A multi-day event shows on each of its days, not after its end.
      List<String> on(int day) => store
          .eventsBetween(DateTime(2026, 11, day), DateTime(2026, 11, day + 1))
          .map((e) => e.title)
          .toList();
      expect(on(19), ['Séminaire']);
      expect(on(20), ['Séminaire']);
      expect(on(21), isEmpty);
      expect(on(16), ['Point hebdo']);

      expect(
        Repeat.monthly.next(DateTime(2026, 12, 15, 9)),
        DateTime(2027, 1, 15, 9),
      );
    });
  });
}
