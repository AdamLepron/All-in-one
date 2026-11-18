import 'media_library.dart';

const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String _plain(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[àâä]'), 'a')
    .replaceAll(RegExp('[îï]'), 'i')
    .replaceAll(RegExp('[ôö]'), 'o')
    .replaceAll(RegExp('[ùûü]'), 'u')
    .replaceAll('ç', 'c');

/// Whether [m] answers [query]: every word of the query must match the
/// file name, its album, its kind ("photo", "vidéo"), or its date (a year
/// such as "2024", a month name, or "2024-07"). Accents and case are ignored.
bool mediaMatches(Media m, String query) {
  final words = _plain(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;
  final d = m.date;
  String two(int n) => n.toString().padLeft(2, '0');
  final haystack = _plain(
    [
      m.name,
      m.album,
      m.video ? 'video videos film' : 'photo photos image',
      '${d.year}',
      _months[d.month - 1],
      '${d.year}-${two(d.month)}',
      '${d.year}-${two(d.month)}-${two(d.day)}',
    ].join(' '),
  );
  return words.every(haystack.contains);
}

/// The items of [list] answering [query], keeping their order.
List<Media> searchMedia(List<Media> list, String query) => query.trim().isEmpty
    ? list
    : [
        for (final m in list)
          if (mediaMatches(m, query)) m,
      ];
