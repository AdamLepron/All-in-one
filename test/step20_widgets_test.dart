import 'dart:convert';

import 'package:all_in_one/core/widget_sync.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OrganizerStore store;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    store = await OrganizerStore.load(file: inMemoryDatabasePath);
  });

  test('snapshot lists open tasks of today and late ones', () {
    final now = DateTime(2026, 5, 10, 9);
    store.tasks = [
      Task(id: 1, title: 'Appeler', due: DateTime(2026, 5, 10)),
      Task(id: 2, title: 'En retard', due: DateTime(2026, 5, 8)),
      Task(id: 3, title: 'Fait', due: DateTime(2026, 5, 10), done: true),
      Task(id: 4, title: 'Demain', due: DateTime(2026, 5, 11)),
    ];
    final snap = widgetSnapshot(store, now);
    expect(snap['tasks'], containsAll(['Appeler', 'En retard']));
    expect(snap['tasks'], isNot(contains('Fait')));
    expect(snap['tasks'], isNot(contains('Demain')));
  });

  test('sync pushes once for identical content', () async {
    final sent = <String>[];
    final sync = WidgetSync(store, send: (j) async => sent.add(j));
    await sync.push();
    await sync.push();
    expect(sent, hasLength(1));
    expect(jsonDecode(sent.single), contains('tasks'));
    sync.dispose();
  });
}
