import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../files/file_ops.dart';

enum CleanCategory {
  duplicates(
    'Doublons',
    'Copies identiques : un exemplaire de chaque est conservé',
  ),
  large('Gros fichiers', 'Fichiers de plus de 50 Mo'),
  oldDownloads(
    'Téléchargements anciens',
    'Dans Téléchargements depuis plus de 90 jours',
  ),
  screenshots("Captures d'écran anciennes", 'Captures de plus de 30 jours'),
  apks("Fichiers d'installation", 'Fichiers APK, inutiles une fois installés'),
  junk(
    'Fichiers temporaires',
    'Fichiers temporaires, journaux et dossiers vides',
  );

  const CleanCategory(this.title, this.description);
  final String title;
  final String description;
}

class CleanItem {
  CleanItem(
    this.path,
    this.size,
    this.modified, {
    this.preselected = true,
    this.group,
  });
  final String path;
  final int size;
  final DateTime modified;

  /// Ticked by default on the review screen.
  final bool preselected;

  /// Duplicates sharing the same content have the same group number.
  final int? group;

  String get name => p.basename(path);
}

class CleanReport {
  CleanReport(this.items);
  final Map<CleanCategory, List<CleanItem>> items;

  /// Bytes freed by removing every preselected item of [category].
  int gain(CleanCategory category) => (items[category] ?? const [])
      .where((i) => i.preselected)
      .fold(0, (sum, i) => sum + i.size);

  /// Preselected bytes over all categories, each file counted once.
  int get totalGain {
    final seen = <String>{};
    var total = 0;
    for (final list in items.values) {
      for (final i in list) {
        if (i.preselected && seen.add(i.path)) total += i.size;
      }
    }
    return total;
  }
}

const largeThreshold = 50 * 1000 * 1000;
const _junkExtensions = {
  '.tmp',
  '.temp',
  '.log',
  '.bak',
  '.crdownload',
  '.part',
};

/// Fingerprint of a file's content. Files over 64 MB are sampled at both
/// ends rather than read whole, which is enough alongside an equal size.
Future<String> _fingerprint(File file, int size) async {
  const limit = 64 * 1024 * 1024;
  const sample = 4 * 1024 * 1024;
  if (size <= limit) return (await md5.bind(file.openRead()).first).toString();
  final head = await file.openRead(0, sample).expand((b) => b).toList();
  final tail = await file
      .openRead(size - sample, size)
      .expand((b) => b)
      .toList();
  return md5.convert([...head, ...tail]).toString();
}

/// Walks [root] and lists what could be removed. Nothing is deleted.
///
/// [onProgress] receives the number of files examined so far.
Future<CleanReport> analyzeStorage(
  String root, {
  DateTime? now,
  void Function(int files)? onProgress,
}) async {
  final today = now ?? DateTime.now();
  final report = {for (final c in CleanCategory.values) c: <CleanItem>[]};
  final bySize = <int, List<(String, DateTime)>>{};
  var count = 0;

  /// Returns true when [dir] holds nothing at all.
  Future<bool> walk(String dir, int depth) async {
    var empty = true;
    try {
      await for (final entity in Directory(dir).list(followLinks: false)) {
        empty = false;
        final name = p.basename(entity.path);
        if (entity is Directory) {
          // System data and the app's own recycle bin are left alone.
          if (depth == 0 && name == 'Android') continue;
          if (name == '.AllInOneTrash') continue;
          if (depth < 12 && await walk(entity.path, depth + 1)) {
            final stat = await entity.stat();
            report[CleanCategory.junk]!.add(
              CleanItem(entity.path, 0, stat.modified),
            );
          }
          continue;
        }
        if (entity is! File) continue;
        final FileStat stat;
        try {
          stat = await entity.stat();
        } on FileSystemException {
          continue;
        }
        count++;
        if (count % 200 == 0) onProgress?.call(count);
        final path = entity.path;
        final item = CleanItem(path, stat.size, stat.modified);
        final age = today.difference(stat.modified).inDays;
        final ext = p.extension(path).toLowerCase();
        final lower = path.toLowerCase();

        if (stat.size >= largeThreshold) {
          // Shown for review but never ticked by default.
          report[CleanCategory.large]!.add(
            CleanItem(path, stat.size, stat.modified, preselected: false),
          );
        }
        if (_junkExtensions.contains(ext) || lower.contains('/.thumbnails/')) {
          report[CleanCategory.junk]!.add(item);
        } else if (ext == '.apk') {
          report[CleanCategory.apks]!.add(item);
        } else if (lower.contains('/screenshots/') && age > 30) {
          report[CleanCategory.screenshots]!.add(item);
        } else if (p.isWithin(p.join(root, 'Download'), path) && age > 90) {
          report[CleanCategory.oldDownloads]!.add(item);
        }
        // Hidden files are not offered as duplicates: apps rely on them.
        if (stat.size > 0 && !lower.contains('/.')) {
          bySize.putIfAbsent(stat.size, () => []).add((path, stat.modified));
        }
      }
    } on FileSystemException {
      return false; // unreadable folder: not ours to judge
    }
    return empty;
  }

  await walk(root, 0);

  // Only files of equal size can be identical, so only those are hashed.
  var group = 0;
  for (final entry in bySize.entries) {
    if (entry.value.length < 2) continue;
    final byHash = <String, List<(String, DateTime)>>{};
    for (final file in entry.value) {
      try {
        final hash = await _fingerprint(File(file.$1), entry.key);
        byHash.putIfAbsent(hash, () => []).add(file);
      } on FileSystemException {
        continue;
      }
    }
    for (final copies in byHash.values) {
      if (copies.length < 2) continue;
      // The oldest copy is treated as the original and kept. Copies made
      // at the same instant are told apart by the shortest path, which is
      // rarely the "name (1)" one.
      copies.sort((a, b) {
        final byDate = a.$2.compareTo(b.$2);
        if (byDate != 0) return byDate;
        final byLength = a.$1.length.compareTo(b.$1.length);
        return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
      });
      for (var i = 0; i < copies.length; i++) {
        report[CleanCategory.duplicates]!.add(
          CleanItem(
            copies[i].$1,
            entry.key,
            copies[i].$2,
            preselected: i > 0,
            group: group,
          ),
        );
      }
      group++;
    }
  }

  for (final list in report.values) {
    list.sort((a, b) => b.size.compareTo(a.size));
  }
  // Keep copies of the same file together, biggest groups first.
  report[CleanCategory.duplicates]!.sort((a, b) {
    final bySize = b.size.compareTo(a.size);
    if (bySize != 0) return bySize;
    final byGroup = a.group!.compareTo(b.group!);
    return byGroup != 0 ? byGroup : a.modified.compareTo(b.modified);
  });
  onProgress?.call(count);
  return CleanReport(report);
}

/// Moves [paths] to the recycle bin; returns how many were moved.
Future<int> cleanToTrash(Iterable<String> paths, Trash trash) async {
  var moved = 0;
  for (final path in paths) {
    try {
      await trash.put(path);
      moved++;
    } on FileSystemException {
      continue; // already gone or read-only
    }
  }
  return moved;
}
