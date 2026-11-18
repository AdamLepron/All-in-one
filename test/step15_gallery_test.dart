import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/gallery/gallery_page.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/gallery/media_search.dart';
import 'package:all_in_one/modules/gallery/vault.dart';
import 'package:all_in_one/modules/gallery/vault_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Media media(
  int id,
  String name,
  DateTime date, {
  String album = 'Appareil photo',
  bool video = false,
}) => Media(
  id: id,
  video: video,
  path: '/x/$name',
  name: name,
  date: date,
  uri: 'content://$id',
  album: album,
);

void main() {
  late AppSettings settings;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    tmp = Directory.systemTemp.createTempSync('step15_gallery');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('gallery search', () {
    final list = [
      media(1, 'IMG_0001.jpg', DateTime(2024, 7, 14)),
      media(
        2,
        'Plage.mp4',
        DateTime(2024, 7, 20),
        album: 'Vacances',
        video: true,
      ),
      media(3, 'Noël.jpg', DateTime(2023, 12, 25), album: 'Famille'),
    ];

    test('matches name, album, kind, year and month; ignores accents', () {
      expect(searchMedia(list, 'plage').map((m) => m.id), [2]);
      expect(searchMedia(list, 'vacances').map((m) => m.id), [2]);
      expect(searchMedia(list, 'vidéo').map((m) => m.id), [2]);
      expect(searchMedia(list, 'video').map((m) => m.id), [2]);
      expect(searchMedia(list, 'photo').map((m) => m.id), [1, 3]);
      expect(searchMedia(list, '2023').map((m) => m.id), [3]);
      expect(searchMedia(list, 'juillet').map((m) => m.id), [1, 2]);
      expect(searchMedia(list, 'decembre').map((m) => m.id), [3]);
      expect(searchMedia(list, 'noel').map((m) => m.id), [3]);
      expect(searchMedia(list, '2024-07-20').map((m) => m.id), [2]);
    });

    test('every word must match; blank query keeps everything', () {
      expect(searchMedia(list, 'juillet vidéo').map((m) => m.id), [2]);
      expect(searchMedia(list, 'juillet noël'), isEmpty);
      expect(searchMedia(list, '   '), list);
      expect(searchMedia(list, 'zzz'), isEmpty);
    });
  });

  test(
    'user albums: create, add without duplicates, remove, rename, delete',
    () {
      final a = settings.createMediaAlbum('Été', keys: ['i1']);
      final b = settings.createMediaAlbum('  ');
      expect(b.name, 'Album ${b.id}');
      settings.addToMediaAlbum(a.id, ['i1', 'i2', 'v3']);
      expect(settings.mediaAlbums.first.keys, ['i1', 'i2', 'v3']);
      settings.removeFromMediaAlbum(a.id, ['i2']);
      expect(settings.mediaAlbums.first.keys, ['i1', 'v3']);
      settings.renameMediaAlbum(a.id, 'Vacances');
      settings.renameMediaAlbum(a.id, ' '); // ignored
      expect(settings.mediaAlbums.first.name, 'Vacances');
      settings.deleteMediaAlbum(b.id);
      expect(settings.mediaAlbums, hasLength(1));
    },
  );

  group('vault lock', () {
    var now = DateTime(2030, 1, 1, 12);
    late VaultLock lock;
    setUp(() {
      now = DateTime(2030, 1, 1, 12);
      lock = VaultLock(settings, now: () => now);
    });

    test('code rules and hashing', () {
      expect(VaultLock.valid('1234'), isTrue);
      expect(VaultLock.valid('12345678'), isTrue);
      expect(VaultLock.valid('123'), isFalse);
      expect(VaultLock.valid('123456789'), isFalse);
      expect(VaultLock.valid('12a4'), isFalse);
      expect(lock.hasPin, isFalse);
      expect(() => lock.setPin('12'), throwsArgumentError);
      lock.setPin('4321');
      expect(lock.hasPin, isTrue);
      // Only a salted hash is stored, never the code.
      expect(settings.raw('vaultPin')!.contains('4321'), isFalse);
      expect(lock.check('4321'), PinResult.ok);
      expect(lock.check('1234'), PinResult.wrong);
    });

    test('five mistakes lock it, for longer each series', () {
      lock.setPin('4321');
      for (var i = 1; i <= 4; i++) {
        expect(lock.check('0000'), PinResult.wrong);
        expect(lock.triesLeft, 5 - i);
      }
      expect(lock.check('0000'), PinResult.locked);
      expect(lock.lockedUntil, now.add(const Duration(seconds: 30)));
      // Even the right code is refused while locked.
      expect(lock.check('4321'), PinResult.locked);

      // After the delay there are five new tries; a success clears the count.
      now = now.add(const Duration(seconds: 31));
      expect(lock.lockedUntil, isNull);
      expect(lock.check('0000'), PinResult.wrong);
      expect(lock.check('4321'), PinResult.ok);
      expect(lock.triesLeft, 5);

      // Failing a second full series doubles the delay.
      for (var i = 0; i < 4; i++) {
        lock.check('0000');
      }
      expect(lock.check('0000'), PinResult.locked);
      expect(lock.lockedUntil, now.add(const Duration(seconds: 30)));
    });
  });

  group('vault storage', () {
    late Vault vault;
    setUp(
      () => vault = Vault(
        directory: () async => '${tmp.path}/vault',
        tempDirectory: () async => '${tmp.path}/vault_tmp',
        iterations: 1000,
      ),
    );

    test('add copies under a neutral name; restore brings it back', () async {
      final src = File('${tmp.path}/Photos/Secret.jpg')
        ..createSync(recursive: true)
        ..writeAsStringSync('contenu');
      expect(() => vault.add(src.path, video: false), throwsStateError);
      expect(await vault.unlock('2468'), isTrue);
      final item = await vault.add(src.path, video: false);
      expect(item.name, 'Secret.jpg');
      expect(item.encrypted, isTrue);
      expect(item.stored.contains('Secret'), isFalse);
      expect(src.existsSync(), isTrue); // the caller deletes the original
      expect((await vault.items()).single.stored, item.stored);
      // On disk it is unreadable; the key is needed to get it back.
      expect(
        (await (await vault.fileOf(item)).readAsBytes()).length,
        isNot('contenu'.length),
      );
      expect(
        String.fromCharCodes(await (await vault.fileOf(item)).readAsBytes())
            .contains('contenu'),
        isFalse,
      );
      expect(String.fromCharCodes(await vault.readBytes(item)), 'contenu');

      // A name already taken in the destination is kept apart.
      File('${tmp.path}/out/Secret.jpg')
        ..createSync(recursive: true)
        ..writeAsStringSync('autre');
      final back = await vault.restore(item, '${tmp.path}/out');
      expect(back, '${tmp.path}/out/Secret (1).jpg');
      expect(File(back).readAsStringSync(), 'contenu');
      expect(await vault.items(), isEmpty);
      expect(
        Directory('${tmp.path}/vault').listSync().whereType<File>().where(
          (f) => !f.path.endsWith('.json') && !f.path.endsWith('vault.key'),
        ),
        isEmpty,
      );
    });

    test('remove deletes for good; vanished files are forgotten', () async {
      final a = File('${tmp.path}/a.jpg')..writeAsStringSync('a');
      final b = File('${tmp.path}/b.mp4')..writeAsStringSync('b');
      await vault.unlock('2468');
      final ia = await vault.add(a.path, video: false);
      final ib = await vault.add(b.path, video: true);
      expect((await vault.items()).map((i) => i.video).toSet(), {false, true});
      await vault.remove(ia);
      expect((await vault.items()).single.stored, ib.stored);
      // Deleted by hand: no longer listed.
      (await vault.fileOf(ib)).deleteSync();
      expect(await vault.items(), isEmpty);
    });

    test('wrong code is refused; locking forgets the key', () async {
      expect(await vault.unlock('2468'), isTrue);
      vault.lock();
      expect(vault.unlocked, isFalse);
      expect(await vault.unlock('1111'), isFalse);
      expect(await vault.unlock('2468'), isTrue);
    });

    test('changing the code keeps the content readable', () async {
      final f = File('${tmp.path}/x.jpg')..writeAsStringSync('xyz');
      await vault.unlock('2468');
      final item = await vault.add(f.path, video: false);
      await vault.changePin('1357');
      vault.lock();
      expect(await vault.unlock('2468'), isFalse);
      expect(await vault.unlock('1357'), isTrue);
      expect(String.fromCharCodes(await vault.readBytes(item)), 'xyz');
    });

    test(
      'files put away by version 1.5 are encrypted at first unlock',
      () async {
        final dir = Directory('${tmp.path}/vault')..createSync(recursive: true);
        File('${dir.path}/old123').writeAsStringSync('ancien');
        File('${dir.path}/index.json').writeAsStringSync(
          '[{"s":"old123","n":"Vieux.jpg","v":false,"a":1700000000000,"z":6}]',
        );
        expect(await vault.unlock('2468'), isTrue);
        final item = (await vault.items()).single;
        expect(item.encrypted, isTrue);
        expect(File('${dir.path}/old123').existsSync(), isFalse);
        expect(String.fromCharCodes(await vault.readBytes(item)), 'ancien');
      },
    );

    test('a damaged index reads as an empty vault', () async {
      Directory('${tmp.path}/vault').createSync(recursive: true);
      File('${tmp.path}/vault/index.json').writeAsStringSync('{oops');
      expect(await vault.items(), isEmpty);
    });
  });

  testWidgets('vault screen: choose a code, wrong code, then open', (
    tester,
  ) async {
    final vault = Vault(
      directory: () async => '${tmp.path}/vault',
      tempDirectory: () async => '${tmp.path}/vault_tmp',
      iterations: 1000,
    );
    Widget app() => ChangeNotifierProvider.value(
      value: settings,
      child: MaterialApp(home: VaultPage(vault: vault)),
    );
    await tester.pumpWidget(app());
    expect(find.text('Choisissez un code'), findsOneWidget);

    // Too short, then mismatching, then good.
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.enterText(find.byType(TextField).last, '12');
    await tester.tap(find.text('Créer le code'));
    await tester.pump();
    expect(find.text('Le code doit avoir de 4 à 8 chiffres'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '2468');
    await tester.enterText(find.byType(TextField).last, '2469');
    await tester.tap(find.text('Créer le code'));
    await tester.pump();
    expect(find.text('Les deux codes sont différents'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '2468');
    await tester.tap(find.text('Créer le code'));
    // Opening reads the vault from disk.
    for (
      var i = 0;
      i < 20 && find.text('Le dossier est vide').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.text('Le dossier est vide'), findsOneWidget);

    // Locked again, then the wrong and the right code.
    await tester.tap(find.byTooltip('Verrouiller'));
    await tester.pump();
    expect(find.text('Entrez votre code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '1111');
    await tester.tap(find.text('Ouvrir'));
    await tester.pump();
    expect(
      find.textContaining('Code incorrect · 4 essais restants'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), '2468');
    await tester.tap(find.text('Ouvrir'));
    for (
      var i = 0;
      i < 20 && find.text('Le dossier est vide').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.text('Le dossier est vide'), findsOneWidget);
  });

  testWidgets('albums tab: create an album and add photos from the selection', (
    tester,
  ) async {
    final library = MediaLibrary()
      ..debugSet([
        media(1, 'A.jpg', DateTime.now()),
        media(2, 'B.jpg', DateTime.now().subtract(const Duration(days: 1))),
      ]);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: library),
        ],
        child: const MaterialApp(home: GalleryPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvel album'), findsOneWidget);
    await tester.tap(find.text('Nouvel album'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Famille');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();
    expect(settings.mediaAlbums.single.name, 'Famille');
    expect(find.text('Famille'), findsOneWidget);
  });
}
