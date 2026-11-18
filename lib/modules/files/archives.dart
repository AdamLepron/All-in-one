import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'file_ops.dart';

/// What an extraction did.
class ExtractResult {
  const ExtractResult(this.files, this.skipped, this.folder);

  /// Files written.
  final int files;

  /// Entries refused because their name would leave the target folder.
  final int skipped;

  /// Folder holding the extracted files.
  final String folder;
}

/// Archive formats that can be opened.
bool canExtract(String path) {
  final n = path.toLowerCase();
  return n.endsWith('.zip') ||
      n.endsWith('.tar') ||
      n.endsWith('.tar.gz') ||
      n.endsWith('.tgz');
}

/// Name of an archive without its extension(s): "photos.tar.gz" → "photos".
String archiveStem(String path) {
  final name = p.basename(path);
  for (final ext in const ['.tar.gz', '.tgz', '.tar', '.zip']) {
    if (name.toLowerCase().endsWith(ext)) {
      return name.substring(0, name.length - ext.length);
    }
  }
  return p.basenameWithoutExtension(name);
}

/// A relative archive entry name made safe, or null when it would escape
/// the target folder ("../x", "/etc/x", drive letters) or is empty.
String? safeEntryName(String name) {
  final unified = name.replaceAll(r'\', '/');
  if (unified.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(unified)) {
    return null;
  }
  final parts = <String>[];
  for (final part in unified.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') return null;
    parts.add(part);
  }
  return parts.isEmpty ? null : parts.join('/');
}

/// Compresses [paths] (files and folders, recursively) into a new zip in
/// [destDir] and returns its path. The archive gets a free name and appears
/// under its final name only once complete.
Future<String> zipEntities(
  List<String> paths,
  String destDir, {
  String? name,
}) async {
  final base =
      name ?? (paths.length == 1 ? p.basename(paths.first) : 'Archive');
  await Directory(destDir).create(recursive: true);
  final target = await uniquePath(destDir, '$base.zip');
  await Isolate.run(() => _zip(paths, target));
  return target;
}

Future<void> _zip(List<String> paths, String target) async {
  final partial = '$target.part';
  final encoder = ZipFileEncoder()..create(partial);
  try {
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      final parent = p.dirname(path);
      if (type == FileSystemEntityType.directory) {
        var empty = true;
        for (final e in Directory(
          path,
        ).listSync(recursive: true, followLinks: false)) {
          if (e is File) {
            empty = false;
            await encoder.addFile(
              e,
              p.relative(e.path, from: parent).replaceAll(r'\', '/'),
            );
          }
        }
        if (empty) {
          // Keeps an empty folder in the archive.
          encoder.addArchiveFile(ArchiveFile.directory('${p.basename(path)}/'));
        }
      } else if (type == FileSystemEntityType.file) {
        await encoder.addFile(File(path), p.basename(path));
      }
    }
  } finally {
    await encoder.close();
  }
  await File(partial).rename(target);
}

/// Extracts [archivePath] into [destDir]. Entries are written under
/// [destDir]; those that try to leave it are skipped, and existing files
/// are never overwritten (the new one gets a free name).
Future<ExtractResult> extractArchive(String archivePath, String destDir) async {
  if (!canExtract(archivePath)) {
    throw const FileSystemException('Format non pris en charge');
  }
  final result = await Isolate.run(() => _extract(archivePath, destDir));
  return ExtractResult(result.$1, result.$2, destDir);
}

(int, int) _extract(String archivePath, String destDir) {
  final lower = archivePath.toLowerCase();
  final Archive archive;
  if (lower.endsWith('.zip')) {
    archive = ZipDecoder().decodeBytes(File(archivePath).readAsBytesSync());
  } else if (lower.endsWith('.tar')) {
    archive = TarDecoder().decodeBytes(File(archivePath).readAsBytesSync());
  } else {
    archive = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(File(archivePath).readAsBytesSync()),
    );
  }
  if (archive.isEmpty) {
    throw const FormatException('Archive vide ou illisible');
  }
  Directory(destDir).createSync(recursive: true);
  var written = 0, skipped = 0;
  for (final entry in archive) {
    final safe = safeEntryName(entry.name);
    if (safe == null) {
      skipped++;
      continue;
    }
    var target = p.join(destDir, safe);
    if (!entry.isFile) {
      Directory(target).createSync(recursive: true);
      continue;
    }
    File(target).parent.createSync(recursive: true);
    // Never replaces a file that is already there.
    var n = 1;
    final stem = p.withoutExtension(target), ext = p.extension(target);
    while (File(target).existsSync()) {
      target = '$stem ($n)$ext';
      n++;
    }
    File(target).writeAsBytesSync(entry.content);
    written++;
  }
  return (written, skipped);
}
