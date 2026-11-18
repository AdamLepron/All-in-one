import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class Note {
  Note({
    this.id,
    this.title = '',
    this.body = '',
    this.color = 0,
    this.pinned = false,
    this.folder = '',
    this.trashedAt,
    List<String>? attachments,
    DateTime? updatedAt,
  }) : attachments = attachments ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  int? id;
  String title;
  String body;

  /// Index into the note colour palette; 0 means no colour.
  int color;
  bool pinned;
  DateTime updatedAt;

  /// Name of the folder holding the note; empty for none.
  String folder;

  /// When the note was thrown away; null for a live note.
  DateTime? trashedAt;

  /// File names inside the notes' attachments directory.
  List<String> attachments;

  bool get inTrash => trashedAt != null;

  bool get isEmpty =>
      title.trim().isEmpty && body.trim().isEmpty && attachments.isEmpty;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'color': color,
    'pinned': pinned ? 1 : 0,
    'updated_at': updatedAt.millisecondsSinceEpoch,
    'folder': folder,
    'trashed_at': trashedAt?.millisecondsSinceEpoch,
    'attachments': jsonEncode(attachments),
  };

  static Note fromMap(Map<String, Object?> m) => Note(
    id: m['id'] as int,
    title: m['title'] as String,
    body: m['body'] as String,
    color: m['color'] as int,
    pinned: m['pinned'] == 1,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    // Absent from databases and backups made before version 1.3.
    folder: (m['folder'] as String?) ?? '',
    trashedAt: m['trashed_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['trashed_at'] as int),
    attachments: _names(m['attachments']),
  );

  static List<String> _names(Object? raw) {
    if (raw is! String || raw.isEmpty) return [];
    try {
      return [for (final n in jsonDecode(raw) as List) n as String];
    } on Object {
      return [];
    }
  }
}

/// How long a note stays in the trash before it is erased.
const trashDelay = Duration(days: 30);

/// Notes persisted in a local SQLite database, kept in memory for instant
/// lists and search.
class NotesStore extends ChangeNotifier {
  NotesStore._(this._db);

  final Database _db;
  List<Note> _all = [];

  /// Live notes: pinned first, then most recently edited.
  List<Note> get notes => [
    for (final n in _all)
      if (!n.inTrash) n,
  ];

  /// Notes in the trash, most recently thrown away first.
  List<Note> get trash => [
    for (final n in _all)
      if (n.inTrash) n,
  ]..sort((a, b) => b.trashedAt!.compareTo(a.trashedAt!));

  /// Names of the folders in use, alphabetically.
  List<String> get folders {
    final names = {
      for (final n in _all)
        if (!n.inTrash && n.folder.isNotEmpty) n.folder,
    }.toList();
    return names..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  /// [file] lets tests use separate databases.
  static Future<NotesStore> open({String file = 'notes.db'}) async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), file),
      version: 2,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'title TEXT NOT NULL, body TEXT NOT NULL, color INTEGER NOT NULL, '
        'pinned INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
        "folder TEXT NOT NULL DEFAULT '', trashed_at INTEGER, "
        "attachments TEXT NOT NULL DEFAULT '[]')",
      ),
      onUpgrade: (db, from, _) async {
        if (from < 2) {
          await db.execute(
            "ALTER TABLE notes ADD COLUMN folder TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('ALTER TABLE notes ADD COLUMN trashed_at INTEGER');
          await db.execute(
            "ALTER TABLE notes ADD COLUMN attachments TEXT NOT NULL DEFAULT '[]'",
          );
        }
      },
    );
    final store = NotesStore._(db);
    await store._reload();
    await store.purgeTrash();
    return store;
  }

  Future<void> _reload() async {
    final rows = await _db.query(
      'notes',
      orderBy: 'pinned DESC, updated_at DESC',
    );
    _all = rows.map(Note.fromMap).toList();
    notifyListeners();
  }

  /// Inserts or updates [note]. Empty notes are discarded.
  Future<void> save(Note note, {bool touch = true}) async {
    if (note.isEmpty) {
      if (note.id != null) await delete(note);
      return;
    }
    if (touch) note.updatedAt = DateTime.now();
    if (note.id == null) {
      note.id = await _db.insert('notes', note.toMap()..remove('id'));
    } else {
      await _db.update(
        'notes',
        note.toMap(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
    }
    await _reload();
  }

  /// Erases a note for good.
  Future<void> delete(Note note) async {
    await _db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    await _reload();
  }

  /// Moves a note to the trash, where it can be brought back.
  Future<void> moveToTrash(Note note) async {
    if (note.id == null) return;
    note.trashedAt = DateTime.now();
    note.pinned = false;
    await save(note, touch: false);
  }

  /// Takes a note out of the trash.
  Future<void> recover(Note note) async {
    note.trashedAt = null;
    await save(note, touch: false);
  }

  /// Erases notes thrown away more than [trashDelay] ago; returns their
  /// attachment names so the files can be removed too.
  Future<List<String>> purgeTrash({DateTime? now}) async {
    final limit = (now ?? DateTime.now()).subtract(trashDelay);
    final old = [
      for (final n in _all)
        if (n.inTrash && n.trashedAt!.isBefore(limit)) n,
    ];
    return _erase(old);
  }

  /// Erases everything in the trash; returns the attachment names.
  Future<List<String>> emptyTrash() => _erase(trash);

  Future<List<String>> _erase(List<Note> doomed) async {
    if (doomed.isEmpty) return const [];
    await _db.transaction((txn) async {
      for (final n in doomed) {
        await txn.delete('notes', where: 'id = ?', whereArgs: [n.id]);
      }
    });
    await _reload();
    return [for (final n in doomed) ...n.attachments];
  }

  /// Puts back a note removed with [delete], keeping its id and date.
  Future<void> restore(Note note) async {
    await _db.insert(
      'notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _reload();
  }

  Future<void> renameFolder(String from, String to) async {
    final name = to.trim();
    if (name.isEmpty || name == from) return;
    await _db.update(
      'notes',
      {'folder': name},
      where: 'folder = ?',
      whereArgs: [from],
    );
    await _reload();
  }

  /// Removes a folder; its notes stay, without a folder.
  Future<void> deleteFolder(String name) async {
    await _db.update(
      'notes',
      {'folder': ''},
      where: 'folder = ?',
      whereArgs: [name],
    );
    await _reload();
  }

  /// Ticks or unticks the [line]th line of a note's checklist.
  Future<void> toggleCheck(Note note, int line) async {
    final lines = note.body.split('\n');
    if (line < 0 || line >= lines.length) return;
    final m = RegExp(r'^(\s*[-*+] )\[([ xX])\]').firstMatch(lines[line]);
    if (m == null) return;
    final next = m[2] == ' ' ? 'x' : ' ';
    lines[line] = lines[line].replaceRange(m.start, m.end, '${m[1]}[$next]');
    note.body = lines.join('\n');
    await save(note, touch: false);
  }

  /// Every note as a plain map, for backups (the trash included).
  List<Map<String, Object?>> exportNotes() => [for (final n in _all) n.toMap()];

  /// Replaces all notes by [rows] (as given by [exportNotes]).
  Future<void> replaceAll(List<Map<String, Object?>> rows) async {
    final notes = [
      for (final r in rows) Note.fromMap(r),
    ]; // validates before deleting
    await _db.transaction((txn) async {
      await txn.delete('notes');
      for (final n in notes) {
        await txn.insert('notes', n.toMap());
      }
    });
    await _reload();
  }

  /// Live notes matching [query]; the trash is not searched.
  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q),
        )
        .toList();
  }
}
