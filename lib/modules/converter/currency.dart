import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/settings.dart';
import 'units.dart';

/// Names of the currencies the European Central Bank publishes rates for.
const currencyNames = <String, String>{
  'EUR': 'Euro',
  'USD': 'Dollar américain',
  'GBP': 'Livre sterling',
  'CHF': 'Franc suisse',
  'JPY': 'Yen',
  'CAD': 'Dollar canadien',
  'AUD': 'Dollar australien',
  'NZD': 'Dollar néo-zélandais',
  'CNY': 'Yuan',
  'INR': 'Roupie indienne',
  'BRL': 'Réal brésilien',
  'MXN': 'Peso mexicain',
  'ZAR': 'Rand sud-africain',
  'TRY': 'Livre turque',
  'SEK': 'Couronne suédoise',
  'NOK': 'Couronne norvégienne',
  'DKK': 'Couronne danoise',
  'PLN': 'Zloty',
  'CZK': 'Couronne tchèque',
  'HUF': 'Forint',
  'RON': 'Leu roumain',
  'BGN': 'Lev bulgare',
  'ISK': 'Couronne islandaise',
  'ILS': 'Shekel',
  'KRW': 'Won sud-coréen',
  'HKD': 'Dollar de Hong Kong',
  'SGD': 'Dollar de Singapour',
  'THB': 'Baht',
  'MYR': 'Ringgit',
  'IDR': 'Roupie indonésienne',
  'PHP': 'Peso philippin',
};

/// Exchange rates: how many units of each currency make one euro.
class CurrencyRates {
  CurrencyRates(this.perEuro, this.date, this.fetched);

  final Map<String, double> perEuro;

  /// Day the rates were published for (the bank's date, as text).
  final String date;

  /// When this phone last downloaded them.
  final DateTime fetched;

  bool get isEmpty => perEuro.isEmpty;

  /// Units usable by the converter. The base is the euro, so a unit's factor
  /// is how many euros one unit is worth.
  List<Unit> get units => [
    for (final code in _ordered)
      Unit(currencyNames[code] ?? code, code, 1 / (perEuro[code] ?? 1)),
  ];

  List<String> get _ordered {
    final codes = perEuro.keys.toList();
    codes.sort((a, b) {
      // Common currencies first, then alphabetical.
      final ia = currencyNames.keys.toList().indexOf(a);
      final ib = currencyNames.keys.toList().indexOf(b);
      if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
      if (ia >= 0) return -1;
      if (ib >= 0) return 1;
      return a.compareTo(b);
    });
    return codes;
  }

  Map<String, Object> toJson() => {
    'rates': perEuro,
    'date': date,
    'fetched': fetched.millisecondsSinceEpoch,
  };

  static CurrencyRates? fromJson(Map<String, dynamic> j) {
    try {
      final rates = {
        for (final e in (j['rates'] as Map).entries)
          e.key as String: (e.value as num).toDouble(),
      }..removeWhere((_, v) => !(v > 0) || v.isInfinite || v.isNaN);
      if (rates.isEmpty) return null;
      rates['EUR'] = 1;
      return CurrencyRates(
        rates,
        (j['date'] as String?) ?? '',
        DateTime.fromMillisecondsSinceEpoch((j['fetched'] as int?) ?? 0),
      );
    } on Object {
      return null;
    }
  }

  /// Reads the answer of the Frankfurter service:
  /// `{"base":"EUR","date":"2025-01-02","rates":{"USD":1.03,...}}`.
  static CurrencyRates? parseFrankfurter(String body, DateTime fetched) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final base = (j['base'] as String?) ?? 'EUR';
      final rates = <String, double>{
        for (final e in (j['rates'] as Map).entries)
          e.key as String: (e.value as num).toDouble(),
      };
      if (base != 'EUR') {
        // Rates given against another currency are brought back to the euro.
        final k = rates['EUR'];
        if (k == null || k <= 0) return null;
        rates.updateAll((_, v) => v / k);
        rates[base] = 1 / k;
      }
      rates['EUR'] = 1;
      return fromJson({
        'rates': rates,
        'date': j['date'] ?? '',
        'fetched': fetched.millisecondsSinceEpoch,
      });
    } on Object {
      return null;
    }
  }
}

/// Downloads rates; returns the response body or throws.
typedef RatesFetcher = Future<String> Function();

/// Daily reference rates (European Central Bank), free and without key.
/// Only currency codes travel over the network, nothing about the user.
Future<String> fetchFrankfurter() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final request = await client
        .getUrl(Uri.parse('https://api.frankfurter.dev/v1/latest?base=EUR'))
        .timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
  } finally {
    client.close(force: true);
  }
}

/// Rates kept on the phone and refreshed at most once every few hours.
class CurrencyStore {
  CurrencyStore(
    this._settings, {
    RatesFetcher? fetcher,
    DateTime Function()? now,
    this.maxAge = const Duration(hours: 12),
  }) : _fetch = fetcher ?? fetchFrankfurter,
       _now = now ?? DateTime.now;

  final AppSettings _settings;
  final RatesFetcher _fetch;
  final DateTime Function() _now;
  final Duration maxAge;

  static const _key = 'currencyRates';

  /// The last rates downloaded, or null if there are none yet.
  CurrencyRates? get cached {
    final raw = _settings.raw(_key);
    if (raw == null) return null;
    try {
      return CurrencyRates.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  bool get stale {
    final c = cached;
    return c == null || _now().difference(c.fetched) > maxAge;
  }

  /// Downloads fresh rates when the cached ones are old (or [force]). On any
  /// failure the cached rates are kept and returned; null if there are none.
  Future<CurrencyRates?> refresh({bool force = false}) async {
    if (!force && !stale) return cached;
    try {
      final body = await _fetch();
      final rates = CurrencyRates.parseFrankfurter(body, _now());
      if (rates != null) {
        _settings.setRaw(_key, jsonEncode(rates.toJson()));
        return rates;
      }
    } on Object {
      // Offline or the service is down: the old rates stay in use.
    }
    return cached;
  }
}
