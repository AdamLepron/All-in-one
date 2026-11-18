import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';

/// A file kept in the protected folder.
class VaultItem {
  const VaultItem({
    required this.stored,
    required this.name,
    required this.video,
    required this.added,
    required this.size,
  });

  /// File name inside the vault folder.
  final String stored;

  /// Name the file had when it was put away.
  final String name;
  final bool video;
  final DateTime added;
  final int size;

  Map<String, Object> toJson() => {
    's': stored,
    'n': name,
    'v': video,
    'a': added.millisecondsSinceEpoch,
    'z': size,
  };

  static VaultItem fromJson(Map<String, dynamic> j) => VaultItem(
    stored: j['s'] as String,
    name: j['n'] as String,
    video: j['v'] as bool? ?? false,
    added: DateTime.fromMillisecondsSinceEpoch(j['a'] as int),
    size: j['z'] as int? ?? 0,
  );
}

/// Result of checking a code.
enum PinResult { ok, wrong, locked }

/// The code protecting the vault: only a salted hash is stored, and
/// repeated mistakes lock the folder for a while.
class VaultLock {
  VaultLock(this._settings, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppSettings _settings;
  final DateTime Function() _now;

  static const _hashKey = 'vaultPin';
  static const _failKey = 'vaultFails';
  static const _untilKey = 'vaultLockedUntil';
  static const maxTries = 5;

  bool get hasPin => _settings.raw(_hashKey) != null;

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// A code is 4 to 8 digits.
  static bool valid(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

  void setPin(String pin) {
    if (!valid(pin)) throw ArgumentError('Code invalide');
    final rng = Random.secure();
    final salt = base64Url.encode([
      for (var i = 0; i < 12; i++) rng.nextInt(256),
    ]);
    _settings.setRaw(_hashKey, '$salt:${_hash(salt, pin)}');
    _settings.setRaw(_failKey, '0');
    _settings.setRaw(_untilKey, '0');
  }

  /// When the vault can be tried again, or null if it is not locked.
  DateTime? get lockedUntil {
    final ms = int.tryParse(_settings.raw(_untilKey) ?? '') ?? 0;
    final until = DateTime.fromMillisecondsSinceEpoch(ms);
    return until.isAfter(_now()) ? until : null;
  }

  PinResult check(String pin) {
    if (lockedUntil != null) return PinResult.locked;
    final stored = _settings.raw(_hashKey);
    if (stored == null) return PinResult.wrong;
    final i = stored.indexOf(':');
    final salt = stored.substring(0, i);
    if (_hash(salt, pin) == stored.substring(i + 1)) {
      _settings.setRaw(_failKey, '0');
      return PinResult.ok;
    }
    final fails = (int.tryParse(_settings.raw(_failKey) ?? '') ?? 0) + 1;
    if (fails % maxTries == 0) {
      // The delay doubles with every further series of mistakes.
      final series = fails ~/ maxTries;
      final seconds = 30 * (1 << (series - 1).clamp(0, 6));
      _settings.setRaw(
        _untilKey,
        '${_now().add(Duration(seconds: seconds)).millisecondsSinceEpoch}',
      );
    }
    _settings.setRaw(_failKey, '$fails');
    return fails % maxTries == 0 ? PinResult.locked : PinResult.wrong;
  }

  /// Tries left before the next lock.
  int get triesLeft {
    final fails = int.tryParse(_settings.raw(_failKey) ?? '') ?? 0;
    return maxTries - fails % maxTries;
  }
}

/// Files moved out of the gallery into the app's private storage, where
/// other apps (and the gallery) cannot see them.
class Vault {
  Vault({Future<String> Function()? directory})
    : _directory = directory ?? (() => locate());

  /// Where the vault lives by default; tests replace it.
  static Future<String> Function() locate = () async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'vault');

  final Future<String> Function() _directory;

  Future<File> _index() async => File(p.join(await _directory(), 'index.json'));

  Future<List<VaultItem>> items() async {
    try {
      final data = jsonDecode(await (await _index()).readAsString()) as List;
      final list = [
        for (final j in data) VaultItem.fromJson(j as Map<String, dynamic>),
      ];
      // Files deleted behind the vault's back are forgotten.
      final dir = await _directory();
      return [
        for (final i in list)
          if (File(p.join(dir, i.stored)).existsSync()) i,
      ]..sort((a, b) => b.added.compareTo(a.added));
    } on Object {
      return [];
    }
  }

  Future<void> _write(List<VaultItem> list) async {
    final index = await _index();
    await index.parent.create(recursive: true);
    final partial = File('${index.path}.part');
    await partial.writeAsString(jsonEncode([for (final i in list) i.toJson()]));
    await partial.rename(index.path);
  }

  Future<File> fileOf(VaultItem item) async =>
      File(p.join(await _directory(), item.stored));

  /// Copies [source] into the vault. The original is left alone: the caller
  /// removes it once this has succeeded.
  Future<VaultItem> add(
    String source, {
    required bool video,
    DateTime? now,
  }) async {
    final dir = Directory(await _directory());
    await dir.create(recursive: true);
    final time = now ?? DateTime.now();
    // Stored under a neutral name so file names do not leak.
    final stored =
        '${time.microsecondsSinceEpoch}${Random().nextInt(1 << 20)}${p.extension(source)}';
    final target = File(p.join(dir.path, stored));
    await File(source).copy(target.path);
    final item = VaultItem(
      stored: stored,
      name: p.basename(source),
      video: video,
      added: time,
      size: await target.length(),
    );
    await _write([...await items(), item]);
    return item;
  }

  /// Takes [item] out of the vault, copying it to [destDir] under its old
  /// name (or a free one), and returns the new path.
  Future<String> restore(VaultItem item, String destDir) async {
    await Directory(destDir).create(recursive: true);
    var target = p.join(destDir, item.name);
    var n = 1;
    final stem = p.basenameWithoutExtension(item.name),
        ext = p.extension(item.name);
    while (File(target).existsSync()) {
      target = p.join(destDir, '$stem ($n)$ext');
      n++;
    }
    await (await fileOf(item)).copy(target);
    await remove(item);
    return target;
  }

  Future<void> remove(VaultItem item) async {
    final f = await fileOf(item);
    if (await f.exists()) await f.delete();
    await _write([
      for (final i in await items())
        if (i.stored != item.stored) i,
    ]);
  }
}
