import 'dart:io';

import 'package:all_in_one/core/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a native crash report is taken into the journal, once', () async {
    final tmp = Directory.systemTemp.createTempSync('nc');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await CrashLog.init(file: File('${tmp.path}/incidents.txt'));
    File('${tmp.path}/native_crash.txt').writeAsStringSync(
      '[2026-11-19 09:00:00] plugin registration\njava.lang.Error: boom\n',
    );
    final text = CrashLog.importNative(tmp);
    expect(text, contains('boom'));
    expect(File('${tmp.path}/native_crash.txt').existsSync(), isFalse);
    expect(CrashLog.read(), contains('boom'));
    expect(CrashLog.count, 1);
    // Nothing more the second time, and an empty file is ignored.
    expect(CrashLog.importNative(tmp), isNull);
    File('${tmp.path}/native_crash.txt').writeAsStringSync('  \n');
    expect(CrashLog.importNative(tmp), isNull);
  });
}
