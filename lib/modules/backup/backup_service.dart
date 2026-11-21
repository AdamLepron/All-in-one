import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../core/settings.dart';
import '../notes/notes_store.dart';
import '../tasks/organizer_store.dart';

/// What a backup file contains, read without restoring it.
class BackupInfo {
  BackupInfo({
    required this.created,
    required this.appVersion,
    required this.notes,
    required this.tasks,
    required this.events,
    required this.files,
  });
  final DateTime created;
  final String appVersion;
  final int notes;
  final int tasks;
  final int events;

  /// Scans and recordings included as files.
  final int files;
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _formatVersion = 1;

/// Saves and restores the data kept by the app: notes, tasks, events,
/// preferences and, optionally, scans and recordings.
///
/// A backup is a zip file with a `data.json` and the files in `scans/` and
/// `recordings/`. Restoring replaces the current data.
class BackupService {
  BackupService({
    required this.notes,
    required this.organizer,
    required this.settings,
    required this.scansDir,
    required this.recordingsDir,
    this.noteFilesDir,
    this.annotationsDir,
    this.appVersion = '3.2.1',
  });

  final NotesStore notes;
  final OrganizerStore organizer;
  final AppSettings settings;
  final String scansDir;
  final String recordingsDir;

  /// Attachments of notes; null leaves them out of backups.
  final String? noteFilesDir;

  /// PDF annotations; null leaves them out of backups.
  final String? annotationsDir;
  final String appVersion;

  /// Writes a backup into [outputDir] and returns its path.
  Future<String> create({
    required String outputDir,
    bool includeFiles = true,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'All-in-One-sauvegarde-${time.year}${two(time.month)}${two(time.day)}-${two(time.hour)}${two(time.minute)}${two(time.second)}.zip';
    await Directory(outputDir).create(recursive: true);
    final target = p.join(outputDir, name);
    final partial = '$target.part';

    final data = {
      'format': _formatVersion,
      'created': time.toIso8601String(),
      'app': appVersion,
      'preferences': settings.exportPrefs(),
      'notes': notes.exportNotes(),
      ...organizer.exportData(),
      'includesFiles': includeFiles,
    };
    final json = File('$partial.json');
    await json.writeAsString(jsonEncode(data));

    final zip = ZipFileEncoder()..create(partial);
    try {
      await zip.addFile(json, 'data.json');
      if (includeFiles) {
        await _addFolder(zip, scansDir, 'scans');
        await _addFolder(zip, recordingsDir, 'recordings');
        if (noteFilesDir != null) {
          await _addFolder(zip, noteFilesDir!, 'note_files');
        }
        if (annotationsDir != null) {
          await _addFolder(zip, annotationsDir!, 'pdf_annotations');
        }
      }
    } finally {
      await zip.close();
      await json.delete();
    }
    // Only a complete file gets its final name.
    await File(partial).rename(target);
    return target;
  }

  Future<void> _addFolder(ZipFileEncoder zip, String dir, String prefix) async {
    final folder = Directory(dir);
    if (!await folder.exists()) return;
    await for (final entity in folder.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        await zip.addFile(
          entity,
          '$prefix/${p.relative(entity.path, from: dir).replaceAll(r'\', '/')}',
        );
      }
    }
  }

  /// Reads the contents of a backup, or throws if it is not one of ours.
  Future<BackupInfo> inspect(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entry = archive.files
          .where((f) => f.isFile && f.name == 'data.json')
          .firstOrNull;
      if (entry == null) {
        throw const BackupException(
          "Ce fichier n'est pas une sauvegarde All-in-One",
        );
      }
      final data = _parse(utf8.decode(entry.content));
      return BackupInfo(
        created:
            DateTime.tryParse(data['created'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        appVersion: data['app'] as String? ?? '?',
        notes: (data['notes'] as List).length,
        tasks: (data['tasks'] as List).length,
        events: (data['events'] as List).length,
        files: archive.files
            .where((f) => f.isFile && f.name != 'data.json')
            .length,
      );
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException(
        "Ce fichier n'est pas une sauvegarde All-in-One lisible",
      );
    } finally {
      await input.close();
    }
  }

  Map<String, dynamic> _parse(String json) {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final format = data['format'];
    if (format is! int) {
      throw const BackupException(
        "Ce fichier n'est pas une sauvegarde All-in-One",
      );
    }
    if (format > _formatVersion) {
      throw const BackupException(
        "Cette sauvegarde vient d'une version plus récente de l'application",
      );
    }
    return data;
  }

  /// Replaces the current data by the backup's. Nothing is changed unless
  /// the whole backup can be read.
  Future<BackupInfo> restore(String zipPath) async {
    final info = await inspect(zipPath); // fails before touching anything
    final work = await Directory.systemTemp.createTemp('restore');
    try {
      await extractFileToDisk(zipPath, work.path);
      final data = _parse(
        await File(p.join(work.path, 'data.json')).readAsString(),
      );
      List<Map<String, Object?>> rows(String key) => [
        for (final r in data[key] as List) (r as Map).cast<String, Object?>(),
      ];

      // Data first; each call validates its rows before deleting anything.
      await notes.replaceAll(rows('notes'));
      await organizer.replaceAll(
        taskRows: rows('tasks'),
        eventRows: rows('events'),
      );
      await settings.replacePrefs(
        (data['preferences'] as Map).cast<String, Object?>(),
      );

      if (data['includesFiles'] == true) {
        await _replaceFolder(p.join(work.path, 'scans'), scansDir);
        await _replaceFolder(p.join(work.path, 'recordings'), recordingsDir);
        if (noteFilesDir != null) {
          await _replaceFolder(p.join(work.path, 'note_files'), noteFilesDir!);
        }
        if (annotationsDir != null) {
          await _replaceFolder(
            p.join(work.path, 'pdf_annotations'),
            annotationsDir!,
          );
        }
      }
      return info;
    } finally {
      await work.delete(recursive: true);
    }
  }

  Future<void> _replaceFolder(String from, String to) async {
    final source = Directory(from);
    if (!await source.exists()) return;
    final target = Directory(to);
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        final dest = File(p.join(to, p.relative(entity.path, from: from)));
        await dest.parent.create(recursive: true);
        await entity.copy(dest.path);
      }
    }
  }
}
