import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/settings.dart';

/// Ad units. The Google test units are used until real ones are given at
/// build time, so a debug or test build never shows (or bills) real ads:
/// `--dart-define=ADMOB_BANNER=ca-app-pub-…/…` and `ADMOB_NATIVE=…`.
class AdUnits {
  static const banner = String.fromEnvironment(
    'ADMOB_BANNER',
    defaultValue: 'ca-app-pub-3940256099942544/9214589741',
  );
  static const native = String.fromEnvironment(
    'ADMOB_NATIVE',
    defaultValue: 'ca-app-pub-3940256099942544/2247696110',
  );
}

/// Starts the ads SDK once the user's consent is settled.
abstract class AdsBackend {
  /// Asks for consent where the law requires it, then initializes the SDK.
  /// True when ads may be requested.
  Future<bool> initialize();

  /// Whether the user can reopen the privacy choices form.
  Future<bool> privacyOptionsAvailable();
  Future<void> showPrivacyOptions();
}

/// Google's own consent form (UMP) and AdMob.
class GoogleAds implements AdsBackend {
  @override
  Future<bool> initialize() async {
    try {
      final info = ConsentInformation.instance;
      final updated = Completer<void>();
      info.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () => updated.complete(),
        (error) => updated.complete(), // go on with what is already known
      );
      await updated.future;
      final shown = Completer<void>();
      ConsentForm.loadAndShowConsentFormIfRequired((_) => shown.complete());
      await shown.future;
      if (!await info.canRequestAds()) return false;
      await MobileAds.instance.initialize();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> privacyOptionsAvailable() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => done.complete());
    return done.future;
  }
}

/// The one-time purchase that removes the ads.
abstract class PurchaseBackend {
  /// Starts listening to purchases and looks up the product.
  Future<void> start();

  /// Becomes true when the purchase is made or restored.
  Stream<bool> get owned;

  /// Price as the store shows it ("2,99 €"), once known.
  String? get price;

  /// Opens the store's purchase sheet. False when it cannot be opened.
  Future<bool> buy();

  /// Asks the store for earlier purchases (new phone, reinstall).
  Future<void> restore();

  void dispose();
}

/// Google Play Billing, through the `in_app_purchase` plugin.
class PlayPurchases implements PurchaseBackend {
  /// The product to create in the Play Console (a one-time "managed" product).
  static const productId = 'remove_ads';

  final InAppPurchase _iap = InAppPurchase.instance;
  final StreamController<bool> _owned = StreamController<bool>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  @override
  Stream<bool> get owned => _owned.stream;

  @override
  String? get price => _product?.price;

  @override
  Future<void> start() async {
    try {
      _sub = _iap.purchaseStream.listen((purchases) async {
        for (final p in purchases) {
          if (p.productID != productId) continue;
          if (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored) {
            _owned.add(true);
          }
          if (p.pendingCompletePurchase) await _iap.completePurchase(p);
        }
      });
      if (await _iap.isAvailable()) {
        final found = await _iap.queryProductDetails({productId});
        _product = found.productDetails.firstOrNull;
      }
    } on Object {
      // No store (emulator, no Play services): the app simply has no purchase.
    }
  }

  @override
  Future<bool> buy() async {
    final product = _product;
    if (product == null) return false;
    try {
      return await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } on Object {
      // Nothing to restore from.
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _owned.close();
  }
}

/// Whether ads are shown, and the purchase that turns them off.
///
/// Nothing is initialized — not even the consent form — for someone who
/// bought the removal: the ads SDK never starts for them.
class AdsController extends ChangeNotifier {
  AdsController(
    this._settings, {
    AdsBackend? ads,
    PurchaseBackend? purchases,
    bool crashed = false,
  }) : _ads = ads ?? GoogleAds(),
       _purchases = purchases ?? PlayPurchases() {
    // A crash that pointed at the ads on an earlier launch: they stay off.
    if (crashed && _settings.raw(_crashKey) != '1') {
      _settings.setRaw(_crashKey, '1');
    }
  }

  static const _key = 'adsRemoved';
  static const _crashKey = 'adsCrashed';

  final AppSettings _settings;
  final AdsBackend _ads;
  final PurchaseBackend _purchases;
  StreamSubscription<bool>? _sub;
  bool _ready = false;
  bool _privacyOptions = false;
  bool _disposed = false;

  /// The ads were removed by a purchase (kept on the device, and restored
  /// from the store on a new one).
  bool get removed => _settings.raw(_key) == '1';

  /// Ads may be shown now.
  bool get canShow => !removed && !disabledByCrash && _ready;

  /// The ads were switched off because they were involved in a crash.
  bool get disabledByCrash => _settings.raw(_crashKey) == '1';

  String? get price => _purchases.price;
  bool get privacyOptionsAvailable => _privacyOptions && !removed;

  /// Called once at launch; never throws, never delays the first frame.
  Future<void> start() async {
    _sub = _purchases.owned.listen((v) {
      if (v) _markRemoved();
    });
    await _purchases.start();
    _notify();
    if (removed || disabledByCrash) return;
    _ready = await _ads.initialize();
    _privacyOptions = await _ads.privacyOptionsAvailable();
    _notify();
  }

  void _markRemoved() {
    if (!removed) _settings.setRaw(_key, '1');
    _ready = false;
    _notify();
  }

  /// Opens the purchase sheet. False when the store is not available.
  Future<bool> buy() => _purchases.buy();

  Future<void> restore() => _purchases.restore();

  Future<void> showPrivacyOptions() => _ads.showPrivacyOptions();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _purchases.dispose();
    super.dispose();
  }
}
