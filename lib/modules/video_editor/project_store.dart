import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_project.dart';

/// A saved montage with the moment it was last changed.
class SavedProject {
  const SavedProject(this.project, this.saved);
  final VideoProject project;
  final DateTime saved;
}

/// Montages kept on the device, one file each, so work can be resumed.
class ProjectStore {
  ProjectStore({Future<String> Function()? directory})
    : _directory = directory ?? (() => locate());

  /// Where projects live by default; tests replace it.
  static Future<String> Function() locate = () async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'video_projects');

  final Future<String> Function() _directory;

  Future<File> _file(String id) async => File(
    p.join(
      await _directory(),
      '${id.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '_')}.json',
    ),
  );

  Future<void> _tail = Future.value();

  /// Saves one after the other, so a late write never overtakes a newer one.
  Future<void> save(VideoProject project, {DateTime? now}) {
    final json = jsonEncode({
      'saved': (now ?? DateTime.now()).millisecondsSinceEpoch,
      'project': project.toJson(),
    });
    final id = project.id;
    return _tail = _tail.catchError((Object _) {}).then((_) async {
      final file = await _file(id);
      await file.parent.create(recursive: true);
      final partial = File('${file.path}.part');
      await partial.writeAsString(json);
      await partial.rename(file.path);
    });
  }

  /// Every readable project, most recently changed first. Damaged files are
  /// skipped.
  Future<List<SavedProject>> list() async {
    final dir = Directory(await _directory());
    if (!await dir.exists()) return [];
    final out = <SavedProject>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        out.add(
          SavedProject(
            VideoProject.fromJson(data['project'] as Map<String, dynamic>),
            DateTime.fromMillisecondsSinceEpoch(data['saved'] as int),
          ),
        );
      } on Object {
        continue;
      }
    }
    return out..sort((a, b) => b.saved.compareTo(a.saved));
  }

  Future<void> delete(String id) {
    return _tail = _tail.catchError((Object _) {}).then((_) async {
      final file = await _file(id);
      if (await file.exists()) await file.delete();
    });
  }
}
