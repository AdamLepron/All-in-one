enum QrKind { url, wifi, email, phone, sms, geo, contact, text }

/// What a scanned code contains and how to present it.
class QrContent {
  QrContent(this.raw) : kind = _kindOf(raw);

  final String raw;
  final QrKind kind;

  static QrKind _kindOf(String raw) {
    final v = raw.trim();
    final lower = v.toLowerCase();
    if (lower.startsWith('wifi:')) return QrKind.wifi;
    if (lower.startsWith('mailto:')) return QrKind.email;
    if (lower.startsWith('tel:')) return QrKind.phone;
    if (lower.startsWith('smsto:') || lower.startsWith('sms:')) {
      return QrKind.sms;
    }
    if (lower.startsWith('geo:')) return QrKind.geo;
    if (lower.startsWith('begin:vcard') || lower.startsWith('mecard:')) {
      return QrKind.contact;
    }
    final uri = Uri.tryParse(v);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return QrKind.url;
    }
    return QrKind.text;
  }

  String get label => switch (kind) {
    QrKind.url => 'Lien',
    QrKind.wifi => 'Réseau Wi-Fi',
    QrKind.email => 'Adresse e-mail',
    QrKind.phone => 'Numéro de téléphone',
    QrKind.sms => 'SMS',
    QrKind.geo => 'Position',
    QrKind.contact => 'Contact',
    QrKind.text => 'Texte',
  };

  /// The contact card of a vCard or MECARD code (kind [QrKind.contact]).
  QrContact? get contact => kind == QrKind.contact ? parseContact(raw) : null;

  /// Number and message of an SMS code: `smsto:+3361234:Bonjour`.
  ({String number, String body}) get sms {
    final v = raw.trim();
    final rest = v.substring(v.indexOf(':') + 1);
    final i = rest.indexOf(':');
    // "sms:+33?body=…" is the other common spelling.
    if (i < 0) {
      final q = rest.indexOf('?');
      final number = q < 0 ? rest : rest.substring(0, q);
      final body = q < 0
          ? ''
          : (Uri.splitQueryString(rest.substring(q + 1))['body'] ?? '');
      return (number: number, body: body);
    }
    return (number: rest.substring(0, i), body: rest.substring(i + 1));
  }

  /// Latitude and longitude of a `geo:48.85,2.35` code, or null.
  ({double lat, double lon})? get geo {
    if (kind != QrKind.geo) return null;
    final m = RegExp(
      r'^geo:(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final lat = double.parse(m[1]!), lon = double.parse(m[2]!);
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return (lat: lat, lon: lon);
  }

  /// Fields of a `WIFI:S:name;T:WPA;P:password;;` code.
  Map<String, String> get wifi {
    final fields = <String, String>{};
    final body = raw.trim().substring(5);
    // Split on unescaped semicolons, then unescape.
    for (final part in body.split(RegExp(r'(?<!\\);'))) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      fields[part.substring(0, i).toUpperCase()] = part
          .substring(i + 1)
          .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
    }
    return fields;
  }

  String get wifiName => wifi['S'] ?? '';
  String get wifiPassword => wifi['P'] ?? '';

  /// Text shown as the main line of a result.
  String get display => switch (kind) {
    QrKind.wifi => wifiName,
    QrKind.email => raw.trim().substring(7).split('?').first,
    QrKind.phone => raw.trim().substring(4),
    QrKind.sms => sms.number,
    QrKind.geo => raw.trim().substring(4),
    QrKind.contact => contact?.name ?? raw.trim(),
    _ => raw.trim(),
  };
}

/// How a Wi-Fi network is protected.
enum WifiSecurity { wpa, wep, open }

/// Builds the text of a Wi-Fi code, escaping reserved characters.
String wifiCode(
  String name,
  String password, {
  WifiSecurity? security,
  bool hidden = false,
}) {
  String esc(String v) =>
      v.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
  // Without a password the network is open, whatever was asked.
  final kind = password.isEmpty
      ? WifiSecurity.open
      : (security ?? WifiSecurity.wpa);
  final type = switch (kind) {
    WifiSecurity.wpa => 'WPA',
    WifiSecurity.wep => 'WEP',
    WifiSecurity.open => 'nopass',
  };
  return 'WIFI:S:${esc(name)};T:$type;'
      '${kind == WifiSecurity.open ? '' : 'P:${esc(password)};'}'
      '${hidden ? 'H:true;' : ''};';
}

/// A contact card, as found in vCard and MECARD codes.
class QrContact {
  const QrContact({
    this.name = '',
    this.phones = const [],
    this.emails = const [],
    this.organization = '',
    this.address = '',
    this.url = '',
  });
  final String name;
  final List<String> phones;
  final List<String> emails;
  final String organization;
  final String address;
  final String url;

  bool get isEmpty =>
      name.isEmpty && phones.isEmpty && emails.isEmpty && organization.isEmpty;
}

/// Reads a vCard (`BEGIN:VCARD…`) or a MECARD (`MECARD:N:Nom,Prénom;…;;`).
QrContact? parseContact(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  if (lower.startsWith('mecard:')) return _parseMecard(text.substring(7));
  if (!lower.startsWith('begin:vcard')) return null;
  var name = '', org = '', address = '', url = '';
  var fn = '';
  final phones = <String>[], emails = <String>[];
  // Lines folded with a leading space continue the previous one.
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');
  String unescape(String v) => v
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
  for (final line in lines) {
    final i = line.indexOf(':');
    if (i <= 0) continue;
    final key = line.substring(0, i).split(';').first.toUpperCase();
    final value = line.substring(i + 1).trim();
    switch (key) {
      case 'FN':
        fn = unescape(value);
      case 'N':
        // Family;Given;Additional;Prefix;Suffix
        final parts = value.split(';').map(unescape).toList();
        final given = parts.length > 1 ? parts[1] : '';
        name = [given, parts.first].where((s) => s.isNotEmpty).join(' ');
      case 'TEL':
        if (value.isNotEmpty) phones.add(unescape(value));
      case 'EMAIL':
        if (value.isNotEmpty) emails.add(unescape(value));
      case 'ORG':
        // Components are separated by plain semicolons; \; is a literal one.
        org = value
            .split(RegExp(r'(?<!\\);'))
            .map(unescape)
            .where((c) => c.trim().isNotEmpty)
            .join(' ');
      case 'ADR':
        address = value
            .split(RegExp(r'(?<!\\);'))
            .map(unescape)
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
      case 'URL':
        url = unescape(value);
    }
  }
  final card = QrContact(
    name: fn.isNotEmpty ? fn : name,
    phones: phones,
    emails: emails,
    organization: org,
    address: address,
    url: url,
  );
  return card.isEmpty ? null : card;
}

QrContact? _parseMecard(String body) {
  var name = '', org = '', address = '', url = '';
  final phones = <String>[], emails = <String>[];
  String unescape(String v) =>
      v.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
  for (final part in body.split(RegExp(r'(?<!\\);'))) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    final key = part.substring(0, i).toUpperCase();
    final value = unescape(part.substring(i + 1));
    switch (key) {
      case 'N':
        // "Nom,Prénom" is turned into "Prénom Nom".
        final p = value.split(',');
        name = p.length > 1 ? '${p[1].trim()} ${p[0].trim()}' : value;
      case 'TEL':
        phones.add(value);
      case 'EMAIL':
        emails.add(value);
      case 'ORG':
        org = value;
      case 'ADR':
        address = value.replaceAll(RegExp(r',\s*'), ', ').trim();
      case 'URL':
        url = value;
    }
  }
  final card = QrContact(
    name: name.trim(),
    phones: phones,
    emails: emails,
    organization: org,
    address: address,
    url: url,
  );
  return card.isEmpty ? null : card;
}

/// Builds a vCard 3.0 code for [c]; reserved characters are escaped.
String vcardCode(QrContact c) {
  String esc(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');
  final parts = c.name.trim().split(RegExp(r'\s+'));
  final family = parts.length > 1 ? parts.last : '';
  final given = parts.length > 1
      ? parts.sublist(0, parts.length - 1).join(' ')
      : parts.first;
  return [
    'BEGIN:VCARD',
    'VERSION:3.0',
    'N:${esc(family)};${esc(given)};;;',
    'FN:${esc(c.name.trim())}',
    if (c.organization.isNotEmpty) 'ORG:${esc(c.organization)}',
    for (final p in c.phones) 'TEL:${esc(p)}',
    for (final e in c.emails) 'EMAIL:${esc(e)}',
    if (c.url.isNotEmpty) 'URL:${esc(c.url)}',
    'END:VCARD',
  ].join('\n');
}
