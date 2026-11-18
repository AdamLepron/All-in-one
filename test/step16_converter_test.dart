import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/converter/converter_page.dart';
import 'package:all_in_one/modules/converter/currency.dart';
import 'package:all_in_one/modules/converter/units.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sample =
    '{"amount":1.0,"base":"EUR","date":"2030-01-02","rates":{"USD":1.25,"GBP":0.8,"JPY":160.0}}';

void main() {
  late AppSettings settings;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
  });

  group('rates', () {
    test('parse the bank answer; euro is added; units convert both ways', () {
      final r = CurrencyRates.parseFrankfurter(
        sample,
        DateTime(2030, 1, 2, 9),
      )!;
      expect(r.perEuro['EUR'], 1);
      expect(r.date, '2030-01-02');
      final units = r.units;
      Unit u(String code) => units.firstWhere((x) => x.symbol == code);
      // 100 EUR → USD, GBP, JPY.
      expect(convert(100, u('EUR'), u('USD')), closeTo(125, 1e-9));
      expect(convert(100, u('EUR'), u('GBP')), closeTo(80, 1e-9));
      expect(convert(160, u('JPY'), u('EUR')), closeTo(1, 1e-9));
      // Across two foreign currencies: 125 USD = 100 EUR = 80 GBP.
      expect(convert(125, u('USD'), u('GBP')), closeTo(80, 1e-9));
      // Common currencies come first, with French names.
      expect(units.first.symbol, 'EUR');
      expect(u('USD').name, 'Dollar américain');
    });

    test('rates against another base are brought back to the euro', () {
      final r = CurrencyRates.parseFrankfurter(
        '{"base":"USD","date":"d","rates":{"EUR":0.8,"GBP":0.64}}',
        DateTime(2030),
      )!;
      expect(r.perEuro['USD'], closeTo(1.25, 1e-9));
      expect(r.perEuro['GBP'], closeTo(0.8, 1e-9));
    });

    test('garbage, empty or absurd answers are refused', () {
      expect(CurrencyRates.parseFrankfurter('nope', DateTime(2030)), isNull);
      expect(
        CurrencyRates.parseFrankfurter(
          '{"rates":{}}',
          DateTime(2030),
        )!.perEuro.length,
        1,
      );
      final bad = CurrencyRates.parseFrankfurter(
        '{"base":"EUR","rates":{"USD":0,"GBP":-1,"JPY":160}}',
        DateTime(2030),
      )!;
      expect(bad.perEuro.keys.toSet(), {'EUR', 'JPY'});
    });
  });

  group('store', () {
    var now = DateTime(2030, 1, 2, 9);
    var calls = 0;
    var fail = false;
    late CurrencyStore store;
    setUp(() {
      now = DateTime(2030, 1, 2, 9);
      calls = 0;
      fail = false;
      store = CurrencyStore(
        settings,
        now: () => now,
        fetcher: () async {
          calls++;
          if (fail) throw Exception('offline');
          return sample;
        },
      );
    });

    test(
      'downloads once, then serves the saved rates until they are old',
      () async {
        expect(store.cached, isNull);
        expect(store.stale, isTrue);
        final a = await store.refresh();
        expect(a!.perEuro['USD'], 1.25);
        expect(calls, 1);
        now = now.add(const Duration(hours: 3));
        expect(store.stale, isFalse);
        await store.refresh();
        expect(calls, 1); // fresh enough
        await store.refresh(force: true);
        expect(calls, 2);
        now = now.add(const Duration(hours: 13));
        expect(store.stale, isTrue);
        await store.refresh();
        expect(calls, 3);
        // Kept across restarts.
        expect(CurrencyStore(settings).cached!.perEuro['JPY'], 160);
      },
    );

    test('offline: the old rates stay in use; with none, null', () async {
      expect(await store.refresh(), isNotNull);
      fail = true;
      now = now.add(const Duration(days: 2));
      final old = await store.refresh();
      expect(old!.perEuro['USD'], 1.25);
      // Nothing downloaded ever.
      SharedPreferences.setMockInitialValues({});
      final fresh = AppSettings(await SharedPreferences.getInstance());
      expect(
        await CurrencyStore(
          fresh,
          fetcher: () async => throw Exception('x'),
        ).refresh(),
        isNull,
      );
    });

    test('a damaged answer does not replace good rates', () async {
      await store.refresh();
      store = CurrencyStore(
        settings,
        now: () => now.add(const Duration(days: 1)),
        fetcher: () async => '<html>captive portal</html>',
      );
      final r = await store.refresh();
      expect(r!.date, '2030-01-02');
    });
  });

  testWidgets('currency category appears and converts using saved rates', (
    tester,
  ) async {
    // Rates already on the phone, so no network is needed.
    final seeded = CurrencyStore(
      settings,
      now: () => DateTime(2030, 1, 2, 9),
      fetcher: () async => sample,
    );
    await tester.runAsync(() => seeded.refresh());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const MaterialApp(home: ConverterPage()),
      ),
    );
    await tester.pump();
    await tester.dragUntilVisible(
      find.text('Devises'),
      find.byWidgetPredicate(
        (w) => w is ListView && w.scrollDirection == Axis.horizontal,
      ),
      const Offset(-200, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devises'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        'Taux de la Banque centrale européenne du 2030-01-02',
      ),
      findsOneWidget,
    );
    // 1 EUR = 1,25 USD.
    expect(find.text('1,25'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
