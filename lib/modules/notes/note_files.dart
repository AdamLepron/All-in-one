import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Files attached to notes, kept in the app's own storage so they survive
/// the original being moved or deleted.
class NoteFiles {
  /// Where attachments live; tests replace it.
  static Future<String> Function() locate = () async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'note_files');

  static Future<String> path() => locate();

  static const imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};

  static bool isImage(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());

  /// Copies [source] into the attachments directory and returns the stored
  /// name. Existing files are never overwritten.
  static Future<String> add(String source) async {
    final dir = Directory(await locate());
    await dir.create(recursive: true);
    final base = p.basenameWithoutExtension(source);
    final ext = p.extension(source);
    var name = '$base$ext';
    var n = 1;
    while (await File(p.join(dir.path, name)).exists()) {
      name = '$base ($n)$ext';
      n++;
    }
    await File(source).copy(p.join(dir.path, name));
    return name;
  }

  static Future<File> file(String name) async =>
      File(p.join(await locate(), p.basename(name)));

  /// Deletes stored files, ignoring those already gone.
  static Future<void> remove(Iterable<String> names) async {
    for (final name in names) {
      try {
        final f = await file(name);
        if (await f.exists()) await f.delete();
      } on FileSystemException {
        // Left behind: harmless.
      }
    }
  }
}
