import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local incident journal. Errors are appended to a file on the device and
/// never sent anywhere: the user can read the file and share it by hand.
class CrashLog {
  CrashLog._();

  static File? _file;

  /// Oldest entries are dropped beyond this size.
  static const maxBytes = 200 * 1024;

  /// Points the journal at [file], or at the app's support folder.
  static Future<void> init({File? file}) async {
    try {
      _file =
          file ??
          File(
            '${(await getApplicationSupportDirectory()).path}/incidents.log',
          );
      await _file!.parent.create(recursive: true);
    } on Object {
      _file = null; // no journal rather than a failure at startup
    }
  }

  /// Hooks Flutter and platform errors. The default console output is kept.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack, source: 'Flutter');
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'Plateforme');
      return true; // handled: the app keeps running
    };
  }

  /// Takes in what the native side wrote about a crash it saw (the file is
  /// removed once read). Returns the text, or null when there was none.
  static String? importNative(Directory dir) {
    try {
      final f = File('${dir.path}/native_crash.txt');
      if (!f.existsSync()) return null;
      final text = f.readAsStringSync();
      f.deleteSync();
      if (text.trim().isEmpty) return null;
      record(text.trim(), null, source: 'Android');
      return text;
    } on Object {
      return null;
    }
  }

  /// Appends one entry. Never throws.
  static void record(Object error, StackTrace? stack, {String source = ''}) {
    final file = _file;
    if (file == null) return;
    try {
      final stamp = DateTime.now().toIso8601String();
      final trace = (stack?.toString() ?? '').split('\n').take(12).join('\n');
      final entry =
          '[$stamp]${source.isEmpty ? '' : ' ($source)'} $error\n$trace\n\n';
      file.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      if (file.lengthSync() > maxBytes) _trim(file);
    } on Object {
      // The journal must never be the cause of a new failure.
    }
  }

  /// Keeps the newest half of the file, starting at an entry boundary.
  static void _trim(File file) {
    final text = file.readAsStringSync();
    final from = text.indexOf('\n\n[', text.length ~/ 2);
    file.writeAsStringSync(from == -1 ? '' : text.substring(from + 2));
  }

  static String read() {
    try {
      return _file != null && _file!.existsSync()
          ? _file!.readAsStringSync()
          : '';
    } on Object {
      return '';
    }
  }

  /// Number of entries in the journal.
  static int get count =>
      RegExp(r'^\[\d{4}-', multiLine: true).allMatches(read()).length;

  static void clear() {
    try {
      if (_file?.existsSync() ?? false) _file!.deleteSync();
    } on Object {
      // Already gone.
    }
  }

  static String? get path => _file?.path;
}
