import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AnnotationKind { highlight, ink, note }

/// A mark on a PDF page. Positions are fractions (0–1) of the page, so
/// they stay put at any zoom level.
class Annotation {
  Annotation({
    required this.kind,
    required this.page,
    required this.color,
    this.rects = const [],
    this.points = const [],
    this.text = '',
  });

  final AnnotationKind kind;

  /// 0-based page.
  final int page;

  /// ARGB colour.
  final int color;

  /// Highlight: the boxes covered.
  final List<Rect> rects;

  /// Ink: the stroke; note: its single position.
  final List<Offset> points;

  /// Note: its text.
  String text;

  Map<String, Object> toJson() => {
    'k': kind.name,
    'p': page,
    'c': color,
    if (rects.isNotEmpty)
      'r': [
        for (final r in rects) [r.left, r.top, r.right, r.bottom],
      ],
    if (points.isNotEmpty)
      'o': [
        for (final o in points) [o.dx, o.dy],
      ],
    if (text.isNotEmpty) 't': text,
  };

  static Annotation fromJson(Map<String, dynamic> j) => Annotation(
    kind: AnnotationKind.values.firstWhere(
      (k) => k.name == j['k'],
      orElse: () => AnnotationKind.note,
    ),
    page: j['p'] as int,
    color: j['c'] as int,
    rects: [
      for (final r in (j['r'] as List? ?? const []))
        Rect.fromLTRB(
          (r[0] as num).toDouble(),
          (r[1] as num).toDouble(),
          (r[2] as num).toDouble(),
          (r[3] as num).toDouble(),
        ),
    ],
    points: [
      for (final o in (j['o'] as List? ?? const []))
        Offset((o[0] as num).toDouble(), (o[1] as num).toDouble()),
    ],
    text: (j['t'] as String?) ?? '',
  );

  /// Whether the page point [at] touches this mark, with [slop] of margin
  /// (also a fraction of the page).
  bool hits(Offset at, double slop) {
    switch (kind) {
      case AnnotationKind.highlight:
        return rects.any((r) => r.inflate(slop).contains(at));
      case AnnotationKind.note:
        return points.isNotEmpty && (points.first - at).distance <= slop * 2;
      case AnnotationKind.ink:
        for (var i = 0; i < points.length; i++) {
          if ((points[i] - at).distance <= slop) return true;
          if (i > 0 && _nearSegment(at, points[i - 1], points[i], slop)) {
            return true;
          }
        }
        return false;
    }
  }
}

bool _nearSegment(Offset p, Offset a, Offset b, double slop) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 == 0) return (p - a).distance <= slop;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  final closest = a + ab * t;
  return (p - closest).distance <= slop;
}

/// Annotations kept next to the app's data, one file per PDF, so the PDF
/// itself is never modified.
class AnnotationStore {
  AnnotationStore({Future<String> Function()? directory})
    : _directory = directory ?? (() => locate());

  /// Where annotations live by default; tests replace it.
  static Future<String> Function() locate = () async => p.join(
    (await getApplicationDocumentsDirectory()).path,
    'pdf_annotations',
  );

  final Future<String> Function() _directory;

  /// Folder holding every annotation file (included in backups).
  Future<String> get directory => _directory();

  Future<File> _file(String pdfPath) async {
    final key = sha1.convert(utf8.encode(pdfPath)).toString();
    return File(p.join(await _directory(), '$key.json'));
  }

  Future<List<Annotation>> load(String pdfPath) async {
    try {
      final data = jsonDecode(await (await _file(pdfPath)).readAsString());
      return [
        for (final a in (data['annotations'] as List))
          Annotation.fromJson(a as Map<String, dynamic>),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> _tail = Future.value();

  /// Saves one after the other: a quick add then undo must end in the order
  /// they were made, not race on the disk.
  Future<void> save(String pdfPath, List<Annotation> list) {
    final snapshot = [...list];
    return _tail = _tail
        .catchError((Object _) {})
        .then((_) => _write(pdfPath, snapshot));
  }

  Future<void> _write(String pdfPath, List<Annotation> list) async {
    final file = await _file(pdfPath);
    if (list.isEmpty) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(
      jsonEncode({
        'pdf': pdfPath,
        'annotations': [for (final a in list) a.toJson()],
      }),
    );
    await partial.rename(file.path);
  }
}
