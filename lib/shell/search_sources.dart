import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../modules/docs/docs_store.dart';
import '../modules/gallery/media_library.dart';
import '../modules/recorder/recorder_controller.dart';
import '../modules/tasks/organizer_store.dart';

bool _has(String? text, String q) =>
    text != null && text.toLowerCase().contains(q);

/// Events whose title, place or notes contain [query], soonest first.
List<Event> searchEvents(List<Event> events, String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return (events
          .where(
            (e) => _has(e.title, q) || _has(e.location, q) || _has(e.notes, q),
          )
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start)))
      .take(limit)
      .toList();
}

/// Photos and videos whose file name or album contains [query].
List<Media> searchMedia(List<Media> items, String query, {int limit = 8}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final hits = <Media>[];
  for (final m in items) {
    if (_has(m.name, q) || _has(m.album, q)) {
      hits.add(m);
      if (hits.length == limit) break;
    }
  }
  return hits;
}

List<Recording> searchRecordings(
  List<Recording> list,
  String query, {
  int limit = 6,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return list.where((r) => _has(r.name, q)).take(limit).toList();
}

/// A short excerpt of [text] around the first occurrence of [query].
String snippetAround(String text, String query, {int radius = 45}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final at = flat.toLowerCase().indexOf(query.trim().toLowerCase());
  if (at < 0) {
    return flat.length > radius * 2
        ? '${flat.substring(0, radius * 2)}…'
        : flat;
  }
  final from = (at - radius).clamp(0, flat.length);
  final to = (at + query.trim().length + radius).clamp(0, flat.length);
  return '${from > 0 ? '…' : ''}${flat.substring(from, to)}${to < flat.length ? '…' : ''}';
}

class DocHit {
  DocHit(this.doc, this.snippet);
  final DocEntry doc;
  final String snippet;
}

/// Documents written in the app, found by title or by their text.
Future<List<DocHit>> searchDocuments(
  String dir,
  String query, {
  int limit = 8,
}) async {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final byTitle = <DocHit>[];
  final byContent = <DocHit>[];
  for (final doc in await listDocuments(dir)) {
    if (doc.title.toLowerCase().contains(q)) {
      byTitle.add(DocHit(doc, doc.preview));
      continue;
    }
    try {
      final file = File(doc.path);
      if (await file.length() > 300 * 1024) {
        continue; // not a note-sized document
      }
      final text = await file.readAsString();
      if (text.toLowerCase().contains(q)) {
        byContent.add(DocHit(doc, snippetAround(text, q)));
      }
    } on Object {
      continue; // unreadable or not text
    }
  }
  return [...byTitle, ...byContent].take(limit).toList();
}

class FileHit {
  FileHit(this.path, this.isDir);
  final String path;
  final bool isDir;
  String get name => p.basename(path);
}

/// Files and folders under [root] whose name contains [query]. Breadth-first,
/// so nearby matches come first; stops at [limit] matches, [maxVisited]
/// entries or [maxTime], whichever comes first. Hidden items, the system
/// Android folder and the app's recycle bin are skipped.
Future<List<FileHit>> searchFileNames(
  String root,
  String query, {
  int limit = 12,
  int maxVisited = 60000,
  Duration maxTime = const Duration(seconds: 3),
}) async {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final hits = <FileHit>[];
  final queue = Queue<String>()..add(root);
  final clock = Stopwatch()..start();
  var visited = 0;
  while (queue.isNotEmpty &&
      hits.length < limit &&
      visited < maxVisited &&
      clock.elapsed < maxTime) {
    final dir = queue.removeFirst();
    try {
      await for (final entity in Directory(dir).list(followLinks: false)) {
        visited++;
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        final isDir = entity is Directory;
        if (isDir && dir == root && name == 'Android') continue;
        if (name.toLowerCase().contains(q)) {
          hits.add(FileHit(entity.path, isDir));
          if (hits.length >= limit) break;
        }
        if (isDir) queue.add(entity.path);
      }
    } on FileSystemException {
      continue; // unreadable folder
    }
  }
  return hits;
}
