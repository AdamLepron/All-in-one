import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const storageRoot = '/storage/emulated/0';

enum FileKind { folder, image, video, audio, document, archive, apk, other }

const _extensions = <FileKind, Set<String>>{
  FileKind.image: {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'heic',
    'heif',
    'avif',
    'bmp',
    'svg',
    'dng',
  },
  FileKind.video: {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'webm',
    'flv',
    'ts',
    '3gp',
    'm4v',
    'wmv',
  },
  FileKind.audio: {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'ogg',
    'opus',
    'wav',
    'aiff',
    'wma',
    'amr',
  },
  FileKind.document: {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
    'rtf',
    'txt',
    'md',
    'csv',
    'epub',
    'mobi',
    'html',
    'json',
    'xml',
  },
  FileKind.archive: {'zip', '7z', 'rar', 'tar', 'gz', 'bz2', 'xz'},
  FileKind.apk: {'apk'},
};

FileKind kindOfPath(String path) {
  final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
  for (final entry in _extensions.entries) {
    if (entry.value.contains(ext)) return entry.key;
  }
  return FileKind.other;
}

class Entry {
  Entry(
    this.path, {
    required this.isDir,
    required this.size,
    required this.modified,
  });

  final String path;
  final bool isDir;

  /// Bytes for a file; number of children for a folder.
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
  bool get hidden => name.startsWith('.');
  FileKind get kind => isDir ? FileKind.folder : kindOfPath(path);
}

enum SortBy { name, date, size }

/// Lists [path], folders first. Entries that cannot be read are skipped.
Future<List<Entry>> listFolder(
  String path, {
  bool showHidden = false,
  SortBy sort = SortBy.name,
  bool ascending = true,
}) async {
  final entries = <Entry>[];
  await for (final entity in Directory(path).list(followLinks: false)) {
    try {
      final stat = await entity.stat();
      final isDir = stat.type == FileSystemEntityType.directory;
      var size = stat.size;
      if (isDir) {
        try {
          size = await Directory(entity.path).list().length;
        } on FileSystemException {
          size = 0;
        }
      }
      final entry = Entry(
        entity.path,
        isDir: isDir,
        size: size,
        modified: stat.modified,
      );
      if (showHidden || !entry.hidden) entries.add(entry);
    } on FileSystemException {
      continue;
    }
  }
  int compare(Entry a, Entry b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    final result = switch (sort) {
      SortBy.name => byName,
      SortBy.date => a.modified.compareTo(b.modified),
      // Folder sizes are child counts, so folders stay sorted by name.
      SortBy.size => a.isDir ? byName : a.size.compareTo(b.size),
    };
    final ordered = result == 0 ? byName : result;
    return ascending ? ordered : -ordered;
  }

  return entries..sort(compare);
}

/// Returns a path in [dir] for [name] that does not exist yet, appending
/// " (1)", " (2)"… before the extension when needed.
Future<String> uniquePath(String dir, String name) async {
  var candidate = p.join(dir, name);
  final base = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  var i = 1;
  while (await FileSystemEntity.type(candidate, followLinks: false) !=
      FileSystemEntityType.notFound) {
    candidate = p.join(dir, '$base ($i)$ext');
    i++;
  }
  return candidate;
}

Future<bool> _isDir(String path) => FileSystemEntity.isDirectory(path);

/// Copies a file or a whole folder into [destDir]; returns the new path.
Future<String> copyEntity(String source, String destDir) async {
  if (await _isDir(source) &&
      (destDir == source || p.isWithin(source, destDir))) {
    throw const FileSystemException(
      'Impossible de copier un dossier dans lui-même',
    );
  }
  final target = await uniquePath(destDir, p.basename(source));
  await _copyTo(source, target);
  return target;
}

Future<void> _copyTo(String source, String target) async {
  if (await _isDir(source)) {
    await Directory(target).create(recursive: true);
    await for (final child in Directory(source).list(followLinks: false)) {
      await _copyTo(child.path, p.join(target, p.basename(child.path)));
    }
  } else {
    await File(source).copy(target);
  }
}

/// Moves a file or folder into [destDir]; returns the new path.
Future<String> moveEntity(String source, String destDir) async {
  if (p.dirname(source) == destDir) return source;
  if (await _isDir(source) &&
      (destDir == source || p.isWithin(source, destDir))) {
    throw const FileSystemException(
      'Impossible de déplacer un dossier dans lui-même',
    );
  }
  final target = await uniquePath(destDir, p.basename(source));
  await _moveTo(source, target);
  return target;
}

Future<void> _moveTo(String source, String target) async {
  final dir = await _isDir(source);
  try {
    dir
        ? await Directory(source).rename(target)
        : await File(source).rename(target);
  } on FileSystemException {
    // Different volume: copy then delete.
    await _copyTo(source, target);
    await deleteForever(source);
  }
}

Future<String> renameEntity(String path, String newName) async {
  final target = p.join(p.dirname(path), newName);
  if (target == path) return path;
  if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
    throw const FileSystemException('Un élément porte déjà ce nom');
  }
  await _moveTo(path, target);
  return target;
}

Future<void> deleteForever(String path) async {
  if (await _isDir(path)) {
    await Directory(path).delete(recursive: true);
  } else {
    await File(path).delete();
  }
}

/// Total size in bytes of a file or of everything inside a folder.
Future<int> sizeOf(String path) async {
  if (!await _isDir(path)) return (await File(path).stat()).size;
  var total = 0;
  await for (final e in Directory(
    path,
  ).list(recursive: true, followLinks: false)) {
    if (e is File) {
      try {
        total += (await e.stat()).size;
      } on FileSystemException {
        continue;
      }
    }
  }
  return total;
}

class TrashItem {
  TrashItem(this.id, this.original, this.deletedAt);
  final String id;
  final String original;
  final DateTime deletedAt;

  String get name => p.basename(original);

  Map<String, Object> toJson() => {
    'id': id,
    'original': original,
    'deletedAt': deletedAt.millisecondsSinceEpoch,
  };

  static TrashItem fromJson(Map<String, dynamic> m) => TrashItem(
    m['id'] as String,
    m['original'] as String,
    DateTime.fromMillisecondsSinceEpoch(m['deletedAt'] as int),
  );
}

/// Recycle bin: deleted items are moved to a hidden folder and can be
/// restored until they are purged.
class Trash {
  Trash(this.dir);

  factory Trash.device() => Trash(p.join(storageRoot, '.AllInOneTrash'));

  final String dir;
  static const retention = Duration(days: 30);

  File get _index => File(p.join(dir, 'index.json'));

  Future<List<TrashItem>> items() async {
    try {
      final list = jsonDecode(await _index.readAsString()) as List;
      return [
        for (final m in list) TrashItem.fromJson(m as Map<String, dynamic>),
      ]..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    } on FileSystemException {
      return [];
    } on FormatException {
      return [];
    }
  }

  Future<void> _write(List<TrashItem> items) async {
    await Directory(dir).create(recursive: true);
    await _index.writeAsString(jsonEncode([for (final i in items) i.toJson()]));
  }

  String pathOf(TrashItem item) => p.join(dir, item.id);

  Future<TrashItem> put(String path) async {
    await Directory(dir).create(recursive: true);
    final now = DateTime.now();
    final item = TrashItem('${now.microsecondsSinceEpoch}', path, now);
    await _moveTo(path, pathOf(item));
    await _write([...await items(), item]);
    return item;
  }

  /// Puts the item back where it was (renamed if the place is taken).
  Future<String> restore(TrashItem item) async {
    final parent = p.dirname(item.original);
    await Directory(parent).create(recursive: true);
    final target = await uniquePath(parent, item.name);
    await _moveTo(pathOf(item), target);
    await _write((await items()).where((i) => i.id != item.id).toList());
    return target;
  }

  Future<void> remove(TrashItem item) async {
    try {
      await deleteForever(pathOf(item));
    } on FileSystemException {
      // Already gone; still drop it from the index.
    }
    await _write((await items()).where((i) => i.id != item.id).toList());
  }

  Future<void> empty() async {
    for (final item in await items()) {
      await remove(item);
    }
  }

  /// Deletes items older than [retention].
  Future<void> purgeExpired() async {
    final limit = DateTime.now().subtract(retention);
    for (final item in await items()) {
      if (item.deletedAt.isBefore(limit)) await remove(item);
    }
  }
}
