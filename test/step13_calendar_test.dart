import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/calendar/calendar_page.dart';
import 'package:all_in_one/modules/calendar/time_grid.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Event ev(String title, DateTime start, DateTime end, {bool allDay = false}) =>
    Event(title: title, start: start, end: end, allDay: allDay);

void main() {
  final day = DateTime(2030, 3, 4); // a Monday

  group('layoutDay', () {
    test('events side by side only when they overlap', () {
      final placed = layoutDay([
        ev('A', DateTime(2030, 3, 4, 9), DateTime(2030, 3, 4, 11)),
        ev('B', DateTime(2030, 3, 4, 10), DateTime(2030, 3, 4, 12)),
        ev('C', DateTime(2030, 3, 4, 11, 30), DateTime(2030, 3, 4, 13)),
        ev('D', DateTime(2030, 3, 4, 15), DateTime(2030, 3, 4, 16)),
      ], day);
      PlacedEvent of(String t) => placed.firstWhere((p) => p.event.title == t);
      // A, B and C chain together: A and B overlap; C starts after A ends
      // so it reuses A's lane.
      expect((of('A').lane, of('A').lanes), (0, 2));
      expect((of('B').lane, of('B').lanes), (1, 2));
      expect((of('C').lane, of('C').lanes), (0, 2));
      // D is alone.
      expect((of('D').lane, of('D').lanes), (0, 1));
      expect(of('A').startMinute, 9 * 60);
      expect(of('A').endMinute, 11 * 60);
    });

    test('short events get a tappable height; all-day ones are left out', () {
      final placed = layoutDay([
        ev('Bref', DateTime(2030, 3, 4, 9), DateTime(2030, 3, 4, 9, 5)),
        ev('Jour', DateTime(2030, 3, 4), DateTime(2030, 3, 5), allDay: true),
      ], day);
      expect(placed, hasLength(1));
      expect(placed.single.endMinute - placed.single.startMinute, 30);
    });

    test('events crossing midnight are cut at the day edges', () {
      final events = [
        ev('Nuit', DateTime(2030, 3, 3, 22), DateTime(2030, 3, 4, 2)),
        ev('Veille', DateTime(2030, 3, 4, 23), DateTime(2030, 3, 5, 1)),
      ];
      final mon = layoutDay(events, day);
      final nuit = mon.firstWhere((p) => p.event.title == 'Nuit');
      expect((nuit.startMinute, nuit.endMinute), (0, 120));
      final veille = mon.firstWhere((p) => p.event.title == 'Veille');
      expect((veille.startMinute, veille.endMinute), (23 * 60, 24 * 60));
      // An event on another day is not placed.
      expect(layoutDay(events, DateTime(2030, 3, 7)), isEmpty);
    });

    test('identical events do not hide each other', () {
      final placed = layoutDay([
        ev('X', DateTime(2030, 3, 4, 9), DateTime(2030, 3, 4, 10)),
        ev('Y', DateTime(2030, 3, 4, 9), DateTime(2030, 3, 4, 10)),
      ], day);
      expect(placed.map((p) => p.lane).toSet(), {0, 1});
      expect(placed.every((p) => p.lanes == 2), isTrue);
    });
  });

  test('all-day strip: all-day events and day-long ones', () {
    final list = allDayOf([
      ev('Férié', DateTime(2030, 3, 4), DateTime(2030, 3, 5), allDay: true),
      ev('Congrès', DateTime(2030, 3, 3, 8), DateTime(2030, 3, 6, 18)),
      ev('Réunion', DateTime(2030, 3, 4, 9), DateTime(2030, 3, 4, 10)),
      ev(
        'Autre jour',
        DateTime(2030, 3, 9),
        DateTime(2030, 3, 10),
        allDay: true,
      ),
    ], day);
    expect(list.map((e) => e.title), ['Férié', 'Congrès']);
  });

  testWidgets('week and day views show events; long press creates one', (
    tester,
  ) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({'calendarPromptHidden': '1'});
    final settings = AppSettings(await SharedPreferences.getInstance());
    late OrganizerStore store;
    final today = DateTime.now();
    await tester.runAsync(() async {
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/org13_cal.db',
      );
      store = await OrganizerStore.load(file: 'org13_cal.db');
      await store.saveEvent(
        ev(
          'Dentiste',
          DateTime(today.year, today.month, today.day, 14),
          DateTime(today.year, today.month, today.day, 15),
        ),
      );
    });
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
        ],
        child: const MaterialApp(home: CalendarPage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Changer de vue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semaine'));
    await tester.pumpAndSettle();
    expect(find.text('Dentiste'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Next week: the event is gone; back: it returns.
    await tester.fling(find.byType(PageView), const Offset(-600, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Dentiste'), findsNothing);
    await tester.fling(find.byType(PageView), const Offset(600, 0), 2000);
    await tester.pumpAndSettle();
    expect(find.text('Dentiste'), findsOneWidget);

    await tester.tap(find.byTooltip('Changer de vue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jour'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dentiste'), findsOneWidget);
    expect(find.textContaining('14:00 – 15:00'), findsOneWidget);

    // Long press on the empty 1 p.m.-ish area of the day column opens the editor.
    final grid = find.byType(TimeGrid);
    await tester.longPressAt(tester.getCenter(grid) + const Offset(0, 30));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Nouvel événement'), findsWidgets);
  });
}
