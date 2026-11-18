import 'dart:io';

import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:all_in_one/shell/search_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  String at(String rel) => '${tmp.path}/$rel';
  void file(String rel, [String content = 'x']) {
    final f = File(at(rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('search_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('events are found by title, place or notes', () {
    final events = [
      Event(
        title: 'Dentiste',
        start: DateTime(2026, 11, 20, 9),
        end: DateTime(2026, 11, 20, 10),
        location: 'Rue Pasteur',
      ),
      Event(
        title: 'Réunion',
        start: DateTime(2026, 12, 1, 9),
        end: DateTime(2026, 12, 1, 10),
        notes: 'apporter le devis du dentiste',
      ),
      Event(
        title: 'Sport',
        start: DateTime(2026, 11, 22),
        end: DateTime(2026, 11, 22, 1),
      ),
    ];
    expect(searchEvents(events, 'dentiste').map((e) => e.title), [
      'Réunion',
      'Dentiste',
    ]); // latest first
    expect(searchEvents(events, 'PASTEUR').single.title, 'Dentiste');
    expect(searchEvents(events, ''), isEmpty);
    expect(searchEvents(events, 'zzz'), isEmpty);
  });

  test('photos, videos and recordings are found by name', () {
    Media m(int id, String name, String album, {bool video = false}) => Media(
      id: id,
      video: video,
      path: '/p/$id',
      name: name,
      date: DateTime(2026),
      uri: 'c://$id',
      album: album,
    );
    final items = [
      m(1, 'IMG_2024_plage.jpg', 'Appareil photo'),
      m(2, 'VID_plage.mp4', 'Films', video: true),
      m(3, 'IMG_ski.jpg', 'Montagne'),
    ];
    expect(searchMedia(items, 'plage').map((x) => x.id), [1, 2]);
    expect(searchMedia(items, 'montagne').single.id, 3); // by album
    expect(searchMedia(items, 'plage', limit: 1).length, 1);
    final recs = [
      Recording('/r/Idée refrain.m4a', Duration.zero, 1, DateTime(2026)),
      Recording('/r/Réunion.m4a', Duration.zero, 1, DateTime(2026)),
    ];
    expect(searchRecordings(recs, 'refrain').single.name, 'Idée refrain');
  });

  test('snippets are centred on the match', () {
    final text = '${'mot ' * 30}important rendez-vous demain ${'suite ' * 30}';
    final s = snippetAround(text, 'rendez-vous');
    expect(s, contains('rendez-vous'));
    expect(s.startsWith('…'), true);
    expect(s.endsWith('…'), true);
    expect(s.length, lessThan(120));
    expect(snippetAround('court texte', 'court'), 'court texte');
    expect(snippetAround('pas trouvé ici', 'zzz'), 'pas trouvé ici');
  });

  test('documents are found by title and by content, titles first', () async {
    file('Courses.md', '# Courses\n\n- pain\n- lait');
    file(
      'Projet.md',
      '# Projet\n\nPenser à la facture du plombier avant vendredi.',
    );
    file('Recettes.txt', 'Courses de Noël');
    file('image.jpg', 'ignoré');
    final hits = await searchDocuments(tmp.path, 'courses');
    expect(hits.map((h) => h.doc.title), ['Courses', 'Recettes']);
    final byContent = await searchDocuments(tmp.path, 'plombier');
    expect(byContent.single.doc.title, 'Projet');
    expect(byContent.single.snippet, contains('plombier'));
    expect(await searchDocuments(tmp.path, 'a'), isEmpty); // too short
    expect(await searchDocuments(at('absent'), 'courses'), isEmpty);
  });

  test(
    'file names are searched nearby first, skipping hidden and system folders',
    () async {
      file('Download/facture-edf.pdf');
      file('Documents/Factures/2026/facture-eau.pdf');
      file('Android/data/app/facture-cachee.pdf');
      file('.trash/facture-corbeille.pdf');
      file('facture-racine.txt');
      Directory(at('Factures anciennes')).createSync();

      final hits = await searchFileNames(tmp.path, 'facture');
      final names = hits.map((h) => h.name).toList();
      expect(
        names.first,
        anyOf('facture-racine.txt', 'Factures anciennes'),
      ); // shallowest first
      expect(
        names,
        containsAll(['facture-edf.pdf', 'facture-eau.pdf', 'Factures']),
      );
      expect(names, isNot(contains('facture-cachee.pdf')));
      expect(names, isNot(contains('facture-corbeille.pdf')));
      expect(
        hits.firstWhere((h) => h.name == 'Factures anciennes').isDir,
        true,
      );

      // The limits stop a runaway search.
      expect((await searchFileNames(tmp.path, 'facture', limit: 2)).length, 2);
      expect(
        (await searchFileNames(tmp.path, 'facture', maxVisited: 3)).length,
        lessThanOrEqualTo(3),
      );
      expect(await searchFileNames(tmp.path, 'f'), isEmpty);
      expect(await searchFileNames(at('absent'), 'facture'), isEmpty);
    },
  );
}
