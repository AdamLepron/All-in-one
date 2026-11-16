enum QrKind { url, wifi, email, phone, text }

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
    QrKind.text => 'Texte',
  };

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
    _ => raw.trim(),
  };
}

/// Builds the text of a Wi-Fi code, escaping reserved characters.
String wifiCode(String name, String password) {
  String esc(String v) =>
      v.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');
  return password.isEmpty
      ? 'WIFI:S:${esc(name)};T:nopass;;'
      : 'WIFI:S:${esc(name)};T:WPA;P:${esc(password)};;';
}
