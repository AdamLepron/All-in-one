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
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  int? id;
  String title;
  String body;

  /// Index into the note colour palette; 0 means no colour.
  int color;
  bool pinned;
  DateTime updatedAt;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  Map<String, Object?> toMap() => {
    'id': id,
    'title': title,
    'body': body,
    'color': color,
    'pinned': pinned ? 1 : 0,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  static Note fromMap(Map<String, Object?> m) => Note(
    id: m['id'] as int,
    title: m['title'] as String,
    body: m['body'] as String,
    color: m['color'] as int,
    pinned: m['pinned'] == 1,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );
}

/// Notes persisted in a local SQLite database, kept in memory for instant
/// lists and search.
class NotesStore extends ChangeNotifier {
  NotesStore._(this._db);

  final Database _db;
  List<Note> _notes = [];

  /// Pinned first, then most recently edited.
  List<Note> get notes => _notes;

  static Future<NotesStore> open() async {
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'notes.db'),
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE notes(id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'title TEXT NOT NULL, body TEXT NOT NULL, color INTEGER NOT NULL, '
        'pinned INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      ),
    );
    final store = NotesStore._(db);
    await store._reload();
    return store;
  }

  Future<void> _reload() async {
    final rows = await _db.query(
      'notes',
      orderBy: 'pinned DESC, updated_at DESC',
    );
    _notes = rows.map(Note.fromMap).toList();
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

  Future<void> delete(Note note) async {
    await _db.delete('notes', where: 'id = ?', whereArgs: [note.id]);
    await _reload();
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

  List<Note> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _notes
        .where(
          (n) =>
              n.title.toLowerCase().contains(q) ||
              n.body.toLowerCase().contains(q),
        )
        .toList();
  }
}
