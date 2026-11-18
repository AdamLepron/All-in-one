import 'dart:async';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/ads/ad_widgets.dart';
import 'package:all_in_one/modules/ads/ads_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAds implements AdsBackend {
  FakeAds({this.allowed = true, this.options = false});
  final bool allowed;
  final bool options;
  int initialized = 0;
  int optionsShown = 0;

  @override
  Future<bool> initialize() async {
    initialized++;
    return allowed;
  }

  @override
  Future<bool> privacyOptionsAvailable() async => options;

  @override
  Future<void> showPrivacyOptions() async => optionsShown++;
}

class FakePurchases implements PurchaseBackend {
  FakePurchases({this.price = '2,99 €', this.canBuy = true});
  @override
  final String? price;
  final bool canBuy;
  final StreamController<bool> stream = StreamController<bool>.broadcast();
  int bought = 0;
  int restored = 0;
  int started = 0;

  @override
  Stream<bool> get owned => stream.stream;

  @override
  Future<void> start() async => started++;

  @override
  Future<bool> buy() async {
    bought++;
    return canBuy;
  }

  @override
  Future<void> restore() async => restored++;

  @override
  void dispose() => stream.close();
}

void main() {
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await AppSettings.load();
  });

  group('controller', () {
    test('ads appear once consent is settled', () async {
      final ads = FakeAds();
      final c = AdsController(settings, ads: ads, purchases: FakePurchases());
      expect(c.canShow, isFalse); // nothing before the SDK is ready
      await c.start();
      expect(ads.initialized, 1);
      expect(c.canShow, isTrue);
      c.dispose();
    });

    test('no consent, no ads', () async {
      final c = AdsController(
        settings,
        ads: FakeAds(allowed: false),
        purchases: FakePurchases(),
      );
      await c.start();
      expect(c.canShow, isFalse);
      c.dispose();
    });

    test('a purchase removes the ads and is remembered', () async {
      final shop = FakePurchases();
      final c = AdsController(settings, ads: FakeAds(), purchases: shop);
      await c.start();
      var notified = 0;
      c.addListener(() => notified++);
      shop.stream.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.removed, isTrue);
      expect(c.canShow, isFalse);
      expect(notified, greaterThan(0));
      expect(settings.raw('adsRemoved'), '1');
      c.dispose();

      // Next launch: the SDK is not even started.
      final ads = FakeAds();
      final again = AdsController(
        settings,
        ads: ads,
        purchases: FakePurchases(),
      );
      await again.start();
      expect(again.removed, isTrue);
      expect(ads.initialized, 0);
      expect(again.canShow, isFalse);
      again.dispose();
    });

    test('buying and restoring go to the store; price comes from it', () async {
      final shop = FakePurchases(price: '1,99 €');
      final c = AdsController(settings, ads: FakeAds(), purchases: shop);
      await c.start();
      expect(shop.started, 1);
      expect(c.price, '1,99 €');
      expect(await c.buy(), isTrue);
      await c.restore();
      expect((shop.bought, shop.restored), (1, 1));
      c.dispose();
    });

    test('privacy choices are offered only while ads exist', () async {
      final ads = FakeAds(options: true);
      final shop = FakePurchases();
      final c = AdsController(settings, ads: ads, purchases: shop);
      await c.start();
      expect(c.privacyOptionsAvailable, isTrue);
      await c.showPrivacyOptions();
      expect(ads.optionsShown, 1);
      shop.stream.add(true);
      await Future<void>.delayed(Duration.zero);
      expect(c.privacyOptionsAvailable, isFalse);
      c.dispose();
    });
  });

  group('widgets', () {
    Widget host(AdsController? ads, Widget child) {
      final page = MaterialApp(home: Scaffold(body: child));
      return ads == null
          ? page
          : ChangeNotifierProvider.value(value: ads, child: page);
    }

    testWidgets('without a controller nothing is drawn and nothing breaks', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          null,
          const Column(
            children: [AdBanner(), NativeAdCard(), AdsSettingsSection()],
          ),
        ),
      );
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Annonce'), findsNothing);
    });

    testWidgets('before the SDK is ready, no space is taken', (tester) async {
      final c = AdsController(
        settings,
        ads: FakeAds(),
        purchases: FakePurchases(),
      );
      await tester.pumpWidget(
        host(
          c,
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [AdBanner(), NativeAdCard()],
          ),
        ),
      );
      expect(tester.getSize(find.byType(Column)).height, 0);
      c.dispose();
    });

    testWidgets('settings: price, purchase, restore', (tester) async {
      final shop = FakePurchases();
      final c = AdsController(settings, ads: FakeAds(), purchases: shop);
      await c.start();
      await tester.pumpWidget(host(c, const AdsSettingsSection()));
      expect(find.text('Supprimer les publicités'), findsOneWidget);
      expect(find.text('Achat unique · 2,99 €'), findsOneWidget);
      await tester.tap(find.text('Supprimer les publicités'));
      await tester.pump();
      expect(shop.bought, 1);
      await tester.tap(find.text('Restaurer mon achat'));
      await tester.pump();
      expect(shop.restored, 1);
      c.dispose();
    });

    testWidgets('settings: a store that cannot sell says so', (tester) async {
      final c = AdsController(
        settings,
        ads: FakeAds(),
        purchases: FakePurchases(price: null, canBuy: false),
      );
      await c.start();
      await tester.pumpWidget(host(c, const AdsSettingsSection()));
      expect(
        find.text('Achat unique · indisponible pour le moment'),
        findsOneWidget,
      );
      await tester.tap(find.text('Supprimer les publicités'));
      await tester.pump();
      expect(find.textContaining("n'est pas disponible"), findsOneWidget);
      c.dispose();
    });

    testWidgets('settings: after the purchase, a thank-you replaces it', (
      tester,
    ) async {
      final shop = FakePurchases();
      final c = AdsController(settings, ads: FakeAds(), purchases: shop);
      await c.start();
      await tester.pumpWidget(host(c, const AdsSettingsSection()));
      shop.stream.add(true);
      await tester.pump();
      await tester.pump();
      expect(find.text('Publicités supprimées'), findsOneWidget);
      expect(find.text('Supprimer les publicités'), findsNothing);
      c.dispose();
    });
  });
}
