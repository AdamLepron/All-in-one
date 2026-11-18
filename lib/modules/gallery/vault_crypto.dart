import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encryption of the protected folder: a random master key encrypts the
/// files (AES-256-GCM, in chunks); the master key itself is stored
/// encrypted with a key derived from the owner's code.
class VaultCrypto {
  static const _magic = [0x41, 0x49, 0x4F, 0x31]; // "AIO1"
  static const chunkSize = 64 * 1024;
  static const _tag = 16;

  static Uint8List randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);
  }

  /// Key made from [pin] and [salt]; slow on purpose.
  static Future<Uint8List> deriveKey(
    String pin,
    Uint8List salt,
    int iterations,
  ) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKeyFromPassword(password: pin, nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Encrypts the 32-byte [master] key with [kek]; returns nonce + cipher + tag.
  static Future<Uint8List> wrap(Uint8List master, Uint8List kek) async {
    final box = await AesGcm.with256bits().encrypt(
      master,
      secretKey: SecretKey(kek),
    );
    return Uint8List.fromList([
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// The master key, or null when [kek] is wrong (the tag does not match).
  static Future<Uint8List?> unwrap(Uint8List wrapped, Uint8List kek) async {
    if (wrapped.length != 12 + 32 + _tag) return null;
    try {
      final box = SecretBox(
        wrapped.sublist(12, 12 + 32),
        nonce: wrapped.sublist(0, 12),
        mac: Mac(wrapped.sublist(12 + 32)),
      );
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: SecretKey(kek),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Uint8List _nonce(Uint8List prefix, int counter) {
    final n = Uint8List(12)..setRange(0, 4, prefix);
    ByteData.sublistView(n).setUint64(4, counter);
    return n;
  }

  /// Additional data binding a chunk to its place: moving, dropping or
  /// repeating chunks is detected.
  static Uint8List _aad(int counter, bool last) {
    final a = Uint8List(9);
    ByteData.sublistView(a).setUint64(0, counter);
    a[8] = last ? 1 : 0;
    return a;
  }

  /// Encrypts [source] into [target] (written as `.part`, then renamed).
  static Future<void> encryptFile(
    String source,
    String target,
    Uint8List key,
  ) => Isolate.run(() => _encryptFile(source, target, key));

  /// Decrypts [source] into [target]. Throws [FormatException] when the file
  /// was altered or the key is wrong.
  static Future<void> decryptFile(
    String source,
    String target,
    Uint8List key,
  ) => Isolate.run(() => _decryptFile(source, target, key));

  /// The decrypted content, for small files such as pictures.
  static Future<Uint8List> decryptToBytes(String source, Uint8List key) =>
      Isolate.run(() => _decryptBytes(source, key));

  static Future<void> _encryptFile(
    String source,
    String target,
    Uint8List key,
  ) async {
    final algo = AesGcm.with256bits();
    final secret = SecretKey(key);
    final input = await File(source).open();
    final partial = File('$target.part');
    final out = partial.openWrite();
    try {
      final length = await input.length();
      final prefix = randomBytes(4);
      out.add(_magic);
      out.add(prefix);
      var counter = 0;
      var offset = 0;
      do {
        final n = min(chunkSize, length - offset);
        final last = offset + n >= length;
        final clear = n == 0 ? Uint8List(0) : await input.read(n);
        offset += n;
        final box = await algo.encrypt(
          clear,
          secretKey: secret,
          nonce: _nonce(prefix, counter),
          aad: _aad(counter, last),
        );
        final len = ByteData(4)..setUint32(0, box.cipherText.length);
        out
          ..add(len.buffer.asUint8List())
          ..add(box.cipherText)
          ..add(box.mac.bytes);
        counter++;
        if (last) break;
      } while (true);
      await out.close();
      await partial.rename(target);
    } catch (_) {
      await out.close().catchError((Object _) {});
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      await input.close();
    }
  }

  static Stream<Uint8List> _chunks(
    RandomAccessFile input,
    Uint8List key,
  ) async* {
    final algo = AesGcm.with256bits();
    final secret = SecretKey(key);
    final total = await input.length();
    final head = await input.read(8);
    if (head.length < 8 || !_listEq(head.sublist(0, 4), _magic)) {
      throw const FormatException('Fichier chiffré invalide');
    }
    final prefix = Uint8List.fromList(head.sublist(4, 8));
    var counter = 0;
    var pos = 8;
    while (pos < total) {
      final lenBytes = await input.read(4);
      if (lenBytes.length < 4) throw const FormatException('Fichier tronqué');
      final len = ByteData.sublistView(Uint8List.fromList(lenBytes))
          .getUint32(0);
      if (len > chunkSize) throw const FormatException('Fichier invalide');
      final body = await input.read(len + _tag);
      if (body.length < len + _tag) {
        throw const FormatException('Fichier tronqué');
      }
      pos += 4 + len + _tag;
      final last = pos >= total;
      try {
        yield Uint8List.fromList(
          await algo.decrypt(
            SecretBox(
              body.sublist(0, len),
              nonce: _nonce(prefix, counter),
              mac: Mac(body.sublist(len)),
            ),
            secretKey: secret,
            aad: _aad(counter, last),
          ),
        );
      } on SecretBoxAuthenticationError {
        throw const FormatException('Fichier modifié ou clé incorrecte');
      }
      counter++;
    }
    if (counter == 0) throw const FormatException('Fichier tronqué');
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Future<void> _decryptFile(
    String source,
    String target,
    Uint8List key,
  ) async {
    final input = await File(source).open();
    final partial = File('$target.part');
    final out = partial.openWrite();
    try {
      await for (final chunk in _chunks(input, key)) {
        out.add(chunk);
      }
      await out.close();
      await partial.rename(target);
    } catch (_) {
      await out.close().catchError((Object _) {});
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      await input.close();
    }
  }

  static Future<Uint8List> _decryptBytes(String source, Uint8List key) async {
    final input = await File(source).open();
    try {
      final out = BytesBuilder(copy: false);
      await for (final chunk in _chunks(input, key)) {
        out.add(chunk);
      }
      return out.takeBytes();
    } finally {
      await input.close();
    }
  }
}
