import 'dart:io';

import 'package:all_in_one/core/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('crash_test');
    await CrashLog.init(file: File('${tmp.path}/incidents.log'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('entries are appended with time, source and a short trace', () {
    expect(CrashLog.read(), '');
    expect(CrashLog.count, 0);
    CrashLog.record(StateError('boom'), StackTrace.current, source: 'Test');
    CrashLog.record('texte simple', null);
    final text = CrashLog.read();
    expect(text, contains('(Test) Bad state: boom'));
    expect(text, contains('texte simple'));
    expect(CrashLog.count, 2);
    // The trace is cut, so one huge stack cannot flood the file.
    expect('\n'.allMatches(text).length, lessThan(40));
  });

  test('the journal stays small and keeps the newest entries', () {
    for (var i = 0; i < 3000; i++) {
      CrashLog.record('incident numéro $i ${'x' * 150}', null);
    }
    final text = CrashLog.read();
    expect(text.length, lessThanOrEqualTo(CrashLog.maxBytes + 400));
    expect(text, contains('numéro 2999'));
    expect(text, isNot(contains('numéro 0 ')));
    // Trimming cuts at an entry boundary: the file starts with an entry.
    expect(text.startsWith('[20'), true);
  });

  test('clearing and a missing file are harmless', () {
    CrashLog.record('a', null);
    CrashLog.clear();
    expect(CrashLog.read(), '');
    CrashLog.clear(); // already gone
    expect(CrashLog.count, 0);
  });

  test('recording never throws, even if the folder disappears', () {
    tmp.deleteSync(recursive: true);
    expect(() => CrashLog.record('x', null), returnsNormally);
    expect(CrashLog.read(), '');
    tmp.createSync();
  });
}
