import 'dart:io';
import 'dart:typed_data';

import 'package:all_in_one/modules/gallery/vault_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late Uint8List key;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('step20_crypto');
    key = VaultCrypto.randomBytes(32);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Uint8List bytes(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) (i * 31 + 7) % 256]);

  String put(String name, Uint8List data) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(data);
    return f.path;
  }

  Future<Uint8List> roundTrip(Uint8List data) async {
    final src = put('plain', data);
    await VaultCrypto.encryptFile(src, '${tmp.path}/enc', key);
    await VaultCrypto.decryptFile('${tmp.path}/enc', '${tmp.path}/dec', key);
    return File('${tmp.path}/dec').readAsBytesSync();
  }

  test('files of every size come back identical', () async {
    for (final n in [
      0,
      1,
      100,
      VaultCrypto.chunkSize - 1,
      VaultCrypto.chunkSize,
      VaultCrypto.chunkSize + 1,
      3 * VaultCrypto.chunkSize + 17,
    ]) {
      expect(await roundTrip(bytes(n)), bytes(n), reason: '$n bytes');
    }
  });

  test('the encrypted file reveals nothing and differs each time', () async {
    final secret = Uint8List.fromList(
      List.generate(50, (_) => 'MOT DE PASSE: 1234').join().codeUnits,
    );
    final src = put('plain', secret);
    await VaultCrypto.encryptFile(src, '${tmp.path}/a', key);
    await VaultCrypto.encryptFile(src, '${tmp.path}/b', key);
    final a = File('${tmp.path}/a').readAsBytesSync();
    final b = File('${tmp.path}/b').readAsBytesSync();
    expect(String.fromCharCodes(a).contains('MOT DE PASSE'), isFalse);
    expect(a, isNot(b)); // fresh random prefix
    expect(a.length, greaterThan(secret.length)); // header and tags
    expect(File('${tmp.path}/a.part').existsSync(), isFalse);
  });

  test('a wrong key is refused and leaves no output', () async {
    await VaultCrypto.encryptFile(
      put('plain', bytes(1000)),
      '${tmp.path}/enc',
      key,
    );
    final other = VaultCrypto.randomBytes(32);
    await expectLater(
      VaultCrypto.decryptFile('${tmp.path}/enc', '${tmp.path}/dec', other),
      throwsA(isA<FormatException>()),
    );
    expect(File('${tmp.path}/dec').existsSync(), isFalse);
    expect(File('${tmp.path}/dec.part').existsSync(), isFalse);
  });

  test('tampering, truncation and reordering are detected', () async {
    final size = 3 * VaultCrypto.chunkSize;
    await VaultCrypto.encryptFile(
      put('plain', bytes(size)),
      '${tmp.path}/enc',
      key,
    );
    final enc = File('${tmp.path}/enc').readAsBytesSync();

    Future<void> mustFail(Uint8List broken) async {
      File('${tmp.path}/x').writeAsBytesSync(broken);
      await expectLater(
        VaultCrypto.decryptFile('${tmp.path}/x', '${tmp.path}/y', key),
        throwsA(isA<FormatException>()),
      );
    }

    // One flipped bit in the middle.
    final flipped = Uint8List.fromList(enc)..[enc.length ~/ 2] ^= 1;
    await mustFail(flipped);
    // The last chunk dropped (the file then ends early).
    final chunkLen = 4 + VaultCrypto.chunkSize + 16;
    await mustFail(Uint8List.sublistView(enc, 0, enc.length - chunkLen));
    // Cut in the middle of a chunk.
    await mustFail(Uint8List.sublistView(enc, 0, enc.length - 100));
    // Two chunks swapped.
    final swapped = Uint8List.fromList(enc);
    swapped.setRange(
      8,
      8 + chunkLen,
      enc.sublist(8 + chunkLen, 8 + 2 * chunkLen),
    );
    swapped.setRange(
      8 + chunkLen,
      8 + 2 * chunkLen,
      enc.sublist(8, 8 + chunkLen),
    );
    await mustFail(swapped);
    // Not an encrypted file at all.
    await mustFail(bytes(500));
    await mustFail(Uint8List(0));
  });

  test('small files can be read straight into memory', () async {
    await VaultCrypto.encryptFile(
      put('plain', bytes(70000)),
      '${tmp.path}/enc',
      key,
    );
    expect(
      await VaultCrypto.decryptToBytes('${tmp.path}/enc', key),
      bytes(70000),
    );
  });

  group('master key wrapping', () {
    test('the code opens it, a wrong one does not', () async {
      final salt = VaultCrypto.randomBytes(16);
      final master = VaultCrypto.randomBytes(32);
      final kek = await VaultCrypto.deriveKey('2468', salt, 1000);
      final wrapped = await VaultCrypto.wrap(master, kek);
      expect(wrapped.length, 12 + 32 + 16);
      expect(await VaultCrypto.unwrap(wrapped, kek), master);
      final wrong = await VaultCrypto.deriveKey('2469', salt, 1000);
      expect(await VaultCrypto.unwrap(wrapped, wrong), isNull);
      expect(await VaultCrypto.unwrap(Uint8List(10), kek), isNull);
    });

    test(
      'derivation depends on code, salt and iterations; is repeatable',
      () async {
        final s1 = Uint8List(16), s2 = Uint8List.fromList(List.filled(16, 1));
        final a = await VaultCrypto.deriveKey('1234', s1, 500);
        expect(await VaultCrypto.deriveKey('1234', s1, 500), a);
        expect(await VaultCrypto.deriveKey('1234', s2, 500), isNot(a));
        expect(await VaultCrypto.deriveKey('1234', s1, 501), isNot(a));
        expect(await VaultCrypto.deriveKey('4321', s1, 500), isNot(a));
        expect(a.length, 32);
      },
    );
  });
}
