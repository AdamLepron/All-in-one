import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/clock/alarms.dart';
import 'package:all_in_one/modules/clock/clock_controller.dart';
import 'package:all_in_one/modules/clock/clock_page.dart';
import 'package:all_in_one/modules/tasks/reminder_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppSettings settings;
  late AlarmStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    store = AlarmStore(settings);
  });

  group('next ring', () {
    // 2030-01-07 is a Monday.
    final monday10 = DateTime(2030, 1, 7, 10);

    test('one-time: today if still ahead, otherwise tomorrow', () {
      expect(
        nextRing(Alarm(hour: 11, minute: 0), monday10),
        DateTime(2030, 1, 7, 11),
      );
      expect(
        nextRing(Alarm(hour: 9, minute: 30), monday10),
        DateTime(2030, 1, 8, 9, 30),
      );
      // Exactly now is already past: never rings "immediately".
      expect(
        nextRing(Alarm(hour: 10, minute: 0), monday10),
        DateTime(2030, 1, 8, 10),
      );
    });

    test('repeating: the next matching weekday', () {
      final wed = Alarm(hour: 7, minute: 0, days: {3});
      expect(nextRing(wed, monday10), DateTime(2030, 1, 9, 7));
      final monOnly = Alarm(hour: 9, minute: 0, days: {1});
      expect(
        nextRing(monOnly, monday10),
        DateTime(2030, 1, 14, 9),
      ); // next week
      final weekend = Alarm(hour: 8, minute: 0, days: {6, 7});
      expect(nextRing(weekend, monday10), DateTime(2030, 1, 12, 8));
    });

    test('across a month end', () {
      final a = Alarm(hour: 6, minute: 0);
      expect(nextRing(a, DateTime(2030, 1, 31, 23)), DateTime(2030, 2, 1, 6));
    });
  });

  test('days are described in French', () {
    expect(daysLabel({}), 'Une fois');
    expect(daysLabel({1, 2, 3, 4, 5, 6, 7}), 'Tous les jours');
    expect(daysLabel({5, 1, 3, 2, 4}), 'En semaine');
    expect(daysLabel({7, 6}), 'Le week-end');
    expect(daysLabel({1, 3}), 'lun, mer');
  });

  test('alarms are saved, sorted by time, updated and deleted', () async {
    final now = DateTime(2030, 1, 7, 10);
    await store.save(Alarm(hour: 18, minute: 0, label: 'Sport'), now: now);
    await store.save(Alarm(hour: 7, minute: 30, days: {1, 2}), now: now);
    expect(store.alarms.map((a) => a.hour), [7, 18]);
    expect(store.alarms.map((a) => a.id).toSet(), hasLength(2));

    final first = store.alarms.first;
    await store.save(first.copy()..minute = 45, now: now);
    expect(store.alarms.first.minute, 45);
    expect(store.alarms, hasLength(2)); // updated, not duplicated

    await store.delete(store.alarms.last);
    expect(store.alarms, hasLength(1));
    // Survives a restart (and so a backup).
    expect(AlarmStore(settings).alarms.single.days, {1, 2});
  });

  test(
    'a one-time alarm that rang while the app was closed switches off',
    () async {
      final now = DateTime(2030, 1, 7, 10);
      await store.save(Alarm(hour: 11, minute: 0), now: now);
      expect(store.alarms.single.enabled, isTrue);
      expect(store.alarms.single.onceAt, DateTime(2030, 1, 7, 11));

      await store.refresh(now: DateTime(2030, 1, 7, 10, 59));
      expect(store.alarms.single.enabled, isTrue);
      await store.refresh(now: DateTime(2030, 1, 7, 11, 5));
      expect(store.alarms.single.enabled, isFalse);

      // Switched back on, it is armed for the next day.
      await store.setEnabled(
        store.alarms.single,
        true,
        now: DateTime(2030, 1, 7, 11, 6),
      );
      expect(store.alarms.single.onceAt, DateTime(2030, 1, 8, 11));
    },
  );

  test('repeating alarms stay on after ringing', () async {
    await store.save(
      Alarm(hour: 7, minute: 0, days: {1, 2, 3, 4, 5}),
      now: DateTime(2030, 1, 7, 6),
    );
    await store.refresh(now: DateTime(2030, 1, 7, 8));
    expect(store.alarms.single.enabled, isTrue);
  });

  test('damaged stored alarms are ignored; bad values are clamped', () async {
    SharedPreferences.setMockInitialValues({'alarms': 'oops'});
    var s = AppSettings(await SharedPreferences.getInstance());
    expect(AlarmStore(s).alarms, isEmpty);
    SharedPreferences.setMockInitialValues({
      'alarms':
          '[{"id":1,"hour":99,"minute":-4,"days":[0,3,9,"x"],"enabled":true}]',
    });
    s = AppSettings(await SharedPreferences.getInstance());
    final a = AlarmStore(s).alarms.single;
    expect(a.hour, 23);
    expect(a.minute, 0);
    expect(a.days, {3});
  });

  test('snooze and stop buttons never throw, even on odd payloads', () async {
    final now = DateTime(2030, 1, 7, 10);
    await handleAlarmAction('alarm_snooze', 'alarm:3|Sport', now: now);
    await handleAlarmAction('alarm_snooze', 'alarm:x|Sport', now: now);
    await handleAlarmAction('alarm_stop', 'alarm:3|', now: now);
    await handleAlarmAction(null, 'alarm:3', now: now);
  });

  testWidgets('several timers run side by side and finish independently', (
    tester,
  ) async {
    final clock = ClockController();
    addTearDown(clock.dispose);
    final tea = clock.addExtra(const Duration(minutes: 3), label: 'Thé');
    final eggs = clock.addExtra(const Duration(minutes: 10), label: 'Œufs');
    expect(clock.extras, hasLength(2));
    expect(tea.running && eggs.running, isTrue);

    await tester.pump(const Duration(minutes: 1));
    // (Remaining time reads the real clock, which the test does not move.)
    expect(tea.running, isTrue);
    eggs.pause();
    expect(eggs.paused, isTrue);

    await tester.pump(const Duration(minutes: 2, seconds: 1));
    expect(tea.ringing, isTrue);
    expect(eggs.ringing, isFalse);
    final frozen = eggs.remaining;
    expect(eggs.remaining, frozen); // a paused timer does not move

    tea.dismiss();
    expect(tea.ringing, isFalse);
    eggs.resume();
    eggs.addMinute();
    expect(eggs.total, const Duration(minutes: 11));
    clock.removeExtra(eggs);
    expect(clock.extras.single, tea);
    tea.restart();
    expect(tea.running, isTrue);
    clock.removeExtra(tea);
    await tester.pump(const Duration(minutes: 20)); // nothing left to fire
  });

  testWidgets('alarms tab: create an alarm, switch it, delete it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider(create: (_) => ClockController()),
        ],
        child: const MaterialApp(home: ClockPage()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Alarmes').last);
    await tester.pumpAndSettle();
    expect(find.text('Aucune alarme'), findsOneWidget);

    await tester.tap(find.byTooltip('Nouvelle alarme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('L')); // Monday
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Réveil');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(store.alarms.single.label, 'Réveil');
    expect(store.alarms.single.days, {1});
    expect(find.textContaining('Réveil · lun'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.alarms.single.enabled, isFalse);

    await tester.drag(find.byType(ListTile), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(store.alarms, isEmpty);
  });
}
