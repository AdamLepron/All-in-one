import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_ops.dart';

/// Ways to look at every file of the phone at once.
enum FileCategory {
  recent('Récents', FileKind.other),
  images('Images', FileKind.image),
  videos('Vidéos', FileKind.video),
  audio('Audio', FileKind.audio),
  documents('Documents', FileKind.document),
  archives('Archives', FileKind.archive),
  apks('Applications', FileKind.apk);

  const FileCategory(this.label, this.kind);
  final String label;
  final FileKind kind;
}

/// Files found in a category, and whether the whole storage was read.
class CategoryScan {
  const CategoryScan(this.entries, {required this.complete});
  final List<Entry> entries;

  /// False when the scan stopped at its limit of files or time.
  final bool complete;
}

/// Files of [category] under [roots], most recent first. [recentDays] is
/// the age limit of the "recent" category. Hidden items, the system
/// Android folder and the app's recycle bin are skipped.
Future<CategoryScan> scanCategory(
  List<String> roots,
  FileCategory category, {
  int limit = 400,
  int maxVisited = 150000,
  Duration maxTime = const Duration(seconds: 8),
  int recentDays = 7,
  DateTime? now,
}) async {
  final since = (now ?? DateTime.now()).subtract(Duration(days: recentDays));
  final found = <Entry>[];
  final clock = Stopwatch()..start();
  var visited = 0;
  var complete = true;
  for (final root in roots) {
    final queue = Queue<String>()..add(root);
    while (queue.isNotEmpty) {
      if (visited >= maxVisited || clock.elapsed >= maxTime) {
        complete = false;
        break;
      }
      final dir = queue.removeFirst();
      try {
        await for (final entity in Directory(dir).list(followLinks: false)) {
          visited++;
          final name = p.basename(entity.path);
          if (name.startsWith('.')) continue;
          if (entity is Directory) {
            if (dir == root && name == 'Android') continue;
            queue.add(entity.path);
            continue;
          }
          if (entity is! File) continue;
          final wanted = category == FileCategory.recent
              ? true
              : kindOfPath(entity.path) == category.kind;
          if (!wanted) continue;
          final stat = await entity.stat();
          if (category == FileCategory.recent &&
              stat.modified.isBefore(since)) {
            continue;
          }
          found.add(
            Entry(
              entity.path,
              isDir: false,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        }
      } on FileSystemException {
        continue; // unreadable folder
      }
    }
  }
  found.sort((a, b) => b.modified.compareTo(a.modified));
  if (found.length > limit) {
    found.removeRange(limit, found.length);
    complete = false;
  }
  return CategoryScan(found, complete: complete);
}

/// A removable volume (SD card, USB drive).
class Volume {
  const Volume(this.path, this.label);
  final String path;
  final String label;
}

/// Volumes mounted next to the internal storage, such as an SD card.
/// Android lists them under /storage with an id like "1A2B-3C4D".
Future<List<Volume>> removableVolumes({String storage = '/storage'}) async {
  final volumes = <Volume>[];
  try {
    await for (final entity in Directory(storage).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is! Directory || name == 'emulated' || name == 'self') {
        continue;
      }
      try {
        // Unreadable (not mounted for us) volumes are not offered.
        await entity.list().first.timeout(
          const Duration(seconds: 2),
          onTimeout: () => entity,
        );
      } on StateError {
        // Empty but readable: still a volume.
      } on FileSystemException {
        continue;
      }
      volumes.add(Volume(entity.path, 'Carte SD ($name)'));
    }
  } on FileSystemException {
    return const [];
  }
  volumes.sort((a, b) => a.path.compareTo(b.path));
  return volumes;
}
