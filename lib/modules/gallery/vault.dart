import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';
import 'vault_crypto.dart';

/// A file kept in the protected folder.
class VaultItem {
  const VaultItem({
    required this.stored,
    required this.name,
    required this.video,
    required this.added,
    required this.size,
    this.encrypted = false,
  });

  /// Whether the stored file is encrypted (files put away before version
  /// 2.0 are plain until the vault is first opened).
  final bool encrypted;

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
    'e': encrypted,
  };

  static VaultItem fromJson(Map<String, dynamic> j) => VaultItem(
    stored: j['s'] as String,
    name: j['n'] as String,
    video: j['v'] as bool? ?? false,
    added: DateTime.fromMillisecondsSinceEpoch(j['a'] as int),
    size: j['z'] as int? ?? 0,
    encrypted: j['e'] as bool? ?? false,
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

/// Files moved out of the gallery (or the file manager) into the app's
/// private storage, encrypted with a key that only the owner's code opens.
class Vault {
  Vault({
    Future<String> Function()? directory,
    Future<String> Function()? tempDirectory,
    this.iterations = 60000,
  }) : _directory = directory ?? (() => locate()),
       _temp = tempDirectory ?? (() => locateTemp());

  /// The vault shared by the whole app, so that unlocking it once is enough
  /// for the screen and for moving files into it.
  static final shared = Vault();

  /// Where the vault lives by default; tests replace it.
  static Future<String> Function() locate = () async =>
      p.join((await getApplicationDocumentsDirectory()).path, 'vault');

  /// Where opened files are decrypted for viewing; wiped on lock.
  static Future<String> Function() locateTemp = () async =>
      p.join((await getTemporaryDirectory()).path, 'vault_view');

  final Future<String> Function() _directory;
  final Future<String> Function() _temp;

  /// Key-derivation cost; high on purpose, lowered by tests.
  final int iterations;

  Uint8List? _master;
  final _thumbs = <String, Uint8List>{};

  bool get unlocked => _master != null;

  Future<File> _keyFile() async =>
      File(p.join(await _directory(), 'vault.key'));

  /// Opens the vault with [pin]. The first time (no key yet) a key is made;
  /// files put away by older versions are encrypted at that point. False
  /// when the code does not open it.
  Future<bool> unlock(String pin) async {
    final file = await _keyFile();
    if (!await file.exists()) {
      final salt = VaultCrypto.randomBytes(16);
      final master = VaultCrypto.randomBytes(32);
      await _writeKey(master, pin, salt);
      _master = master;
    } else {
      try {
        final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final kek = await VaultCrypto.deriveKey(
          pin,
          base64Decode(j['salt'] as String),
          j['iter'] as int,
        );
        final master = await VaultCrypto.unwrap(
          base64Decode(j['wrapped'] as String),
          kek,
        );
        if (master == null) return false;
        _master = master;
      } on Object {
        return false;
      }
    }
    await _encryptOldFiles();
    return true;
  }

  Future<void> _writeKey(Uint8List master, String pin, Uint8List salt) async {
    final kek = await VaultCrypto.deriveKey(pin, salt, iterations);
    final wrapped = await VaultCrypto.wrap(master, kek);
    final file = await _keyFile();
    await file.parent.create(recursive: true);
    final partial = File('${file.path}.part');
    await partial.writeAsString(
      jsonEncode({
        'v': 1,
        'salt': base64Encode(salt),
        'iter': iterations,
        'wrapped': base64Encode(wrapped),
      }),
    );
    await partial.rename(file.path);
  }

  /// Another code: the master key is wrapped again, files stay as they are.
  Future<void> changePin(String newPin) async {
    final master = _master;
    if (master == null) throw StateError('Coffre verrouillé');
    await _writeKey(master, newPin, VaultCrypto.randomBytes(16));
  }

  /// Forgets the key and every decrypted copy.
  Future<void> lock() async {
    _master = null;
    _thumbs.clear();
    try {
      final dir = Directory(await _temp());
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      // Nothing more to do.
    }
  }

  Future<void> _encryptOldFiles() async {
    final all = await _readAll();
    var changed = false;
    final dir = await _directory();
    for (var i = 0; i < all.length; i++) {
      final item = all[i];
      if (item.encrypted) continue;
      final plain = File(p.join(dir, item.stored));
      if (!await plain.exists()) continue;
      final target = '${plain.path}.aio';
      await VaultCrypto.encryptFile(plain.path, target, _master!);
      await plain.delete();
      all[i] = VaultItem(
        stored: '${item.stored}.aio',
        name: item.name,
        video: item.video,
        added: item.added,
        size: item.size,
        encrypted: true,
      );
      changed = true;
    }
    if (changed) await _write(all);
  }

  Future<File> _index() async => File(p.join(await _directory(), 'index.json'));

  Future<List<VaultItem>> _readAll() async {
    try {
      final data = jsonDecode(await (await _index()).readAsString()) as List;
      return [
        for (final j in data) VaultItem.fromJson(j as Map<String, dynamic>),
      ];
    } on Object {
      return [];
    }
  }

  Future<List<VaultItem>> items() async {
    final dir = await _directory();
    return [
      for (final i in await _readAll())
        if (File(p.join(dir, i.stored)).existsSync()) i,
    ]..sort((a, b) => b.added.compareTo(a.added));
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

  /// Encrypts [source] into the vault. The original is left alone: the
  /// caller removes it once this has succeeded.
  Future<VaultItem> add(
    String source, {
    required bool video,
    DateTime? now,
  }) async {
    final master = _master;
    if (master == null) throw StateError('Coffre verrouillé');
    final dir = Directory(await _directory());
    await dir.create(recursive: true);
    final time = now ?? DateTime.now();
    // Stored under a neutral name so file names do not leak.
    final stored =
        '${time.microsecondsSinceEpoch}${Random().nextInt(1 << 20)}.aio';
    final target = p.join(dir.path, stored);
    final size = await File(source).length();
    await VaultCrypto.encryptFile(source, target, master);
    final item = VaultItem(
      stored: stored,
      name: p.basename(source),
      video: video,
      added: time,
      size: size,
      encrypted: true,
    );
    await _write([...await _readAll(), item]);
    return item;
  }

  /// A decrypted copy of [item] for viewing, in a temporary folder that is
  /// emptied when the vault locks. The copy keeps the original extension.
  Future<File> decryptToTemp(VaultItem item) async {
    final master = _master;
    if (master == null) throw StateError('Coffre verrouillé');
    final dir = Directory(await _temp());
    await dir.create(recursive: true);
    final target = p.join(dir.path, '${item.stored}${p.extension(item.name)}');
    if (!File(target).existsSync()) {
      await VaultCrypto.decryptFile((await fileOf(item)).path, target, master);
    }
    return File(target);
  }

  /// The decrypted content of a small file (a picture).
  Future<Uint8List> readBytes(VaultItem item) async {
    final master = _master;
    if (master == null) throw StateError('Coffre verrouillé');
    return VaultCrypto.decryptToBytes((await fileOf(item)).path, master);
  }

  /// Decrypted bytes of a picture, kept in memory while the vault is open.
  Future<Uint8List> thumbnail(VaultItem item) async =>
      _thumbs[item.stored] ??= await readBytes(item);

  /// Takes [item] out of the vault, writing it to [destDir] under its old
  /// name (or a free one), and returns the new path.
  Future<String> restore(VaultItem item, String destDir) async {
    final master = _master;
    if (master == null) throw StateError('Coffre verrouillé');
    await Directory(destDir).create(recursive: true);
    var target = p.join(destDir, item.name);
    var n = 1;
    final stem = p.basenameWithoutExtension(item.name),
        ext = p.extension(item.name);
    while (File(target).existsSync()) {
      target = p.join(destDir, '$stem ($n)$ext');
      n++;
    }
    await VaultCrypto.decryptFile((await fileOf(item)).path, target, master);
    await remove(item);
    return target;
  }

  Future<void> remove(VaultItem item) async {
    final f = await fileOf(item);
    if (await f.exists()) await f.delete();
    _thumbs.remove(item.stored);
    await _write([
      for (final i in await _readAll())
        if (i.stored != item.stored) i,
    ]);
  }
}
