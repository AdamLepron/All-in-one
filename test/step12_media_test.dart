import 'dart:io';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/equalizer/equalizer_controller.dart';
import 'package:all_in_one/modules/music/lyrics.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/video/subtitles.dart';
import 'package:all_in_one/modules/video/video_player_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('step12');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('subtitles', () {
    test('finds files named like the video, with their language', () {
      for (final n in [
        'film.mp4',
        'film.srt',
        'film.fr.srt',
        'film.English.vtt',
        'film.txt',
        'autre.srt',
        'filmographie.srt',
      ]) {
        File('${tmp.path}/$n').writeAsStringSync('x');
      }
      final found = findSubtitles('${tmp.path}/film.mp4');
      // Sorted by file name: film.English.vtt, film.fr.srt, film.srt.
      expect(found.map((f) => f.label), ['English', 'fr', 'Sous-titres']);
    });

    test('a folder that cannot be read gives an empty list', () {
      expect(findSubtitles('${tmp.path}/absent/film.mp4'), isEmpty);
    });

    test('reads UTF-8 and falls back to Latin-1', () async {
      final utf = File('${tmp.path}/a.srt')..writeAsStringSync('é à ç');
      expect(await readSubtitleText(utf.path), 'é à ç');
      final latin = File('${tmp.path}/b.srt')
        ..writeAsBytesSync([0xE9, 0x20, 0xE0]); // "é à" in Latin-1
      expect(await readSubtitleText(latin.path), 'é à');
    });

    test('parses SubRip and WebVTT', () {
      const srt =
          '1\n00:00:01,000 --> 00:00:03,000\nBonjour\n\n2\n00:00:04,000 --> 00:00:05,500\nSalut\n';
      final a = parseSubtitles('x.srt', srt);
      expect(a.captions.map((c) => c.text), ['Bonjour', 'Salut']);
      expect(a.captions.first.start, const Duration(seconds: 1));
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:02.000\nHello\n\n';
      final b = parseSubtitles('x.VTT', vtt);
      expect(b.captions.single.text, 'Hello');
    });
  });

  test('audio track names are readable', () {
    VideoAudioTrack t({String? label, String? lang, int? ch}) =>
        VideoAudioTrack(
          id: '1',
          label: label,
          language: lang,
          isSelected: false,
          channelCount: ch,
        );
    expect(trackName(t(label: 'Français'), 0), 'Français');
    expect(trackName(t(lang: 'en'), 1), 'EN');
    expect(trackName(t(lang: 'und'), 1), 'Piste 2');
    expect(trackName(t(label: 'VO', ch: 6), 0), 'VO · 6 canaux');
  });

  group('lyrics', () {
    test('synchronised lines, several stamps, offset and metadata', () {
      final l = parseLyrics(
        '[ar:Moi]\n[offset:500]\n[00:10.00]Deux\n[00:01.50][00:20.5]Un\n\n[00:30]Trois',
      );
      expect(l.synced, isTrue);
      expect(l.lines.map((x) => x.text), ['Un', 'Deux', 'Un', 'Trois']);
      // The offset moves every line earlier by 500 ms.
      expect(l.lines.first.time, const Duration(seconds: 1));
      expect(l.lines[1].time, const Duration(milliseconds: 9500));
    });

    test('the active line follows the position', () {
      final l = parseLyrics('[00:05.00]A\n[00:10.00]B\n[00:15.00]C');
      expect(l.activeAt(Duration.zero), -1);
      expect(l.activeAt(const Duration(seconds: 5)), 0);
      expect(l.activeAt(const Duration(seconds: 12)), 1);
      expect(l.activeAt(const Duration(minutes: 9)), 2);
    });

    test('plain text keeps its lines and is not synchronised', () {
      final l = parseLyrics('\n\nPremier\n\nSecond\n\n');
      expect(l.synced, isFalse);
      expect(l.lines.map((x) => x.text), ['Premier', '', 'Second']);
      expect(l.activeAt(const Duration(seconds: 3)), -1);
      expect(parseLyrics('').isEmpty, isTrue);
    });

    test('finds the .lrc beside the song and reads it', () async {
      File('${tmp.path}/chanson.mp3').writeAsStringSync('x');
      expect(findLyricsFile('${tmp.path}/chanson.mp3'), isNull);
      File('${tmp.path}/chanson.lrc').writeAsStringSync('﻿[00:01.00]Oui');
      final path = findLyricsFile('${tmp.path}/chanson.mp3');
      expect(path, endsWith('chanson.lrc'));
      expect((await readLyrics(path!)).lines.single.text, 'Oui');
      expect(findLyricsFile(''), isNull);
    });
  });

  group('equalizer presets and output profiles', () {
    late AppSettings settings;
    late MusicController music;
    late EqualizerController eq;
    var output = {'type': 'speaker', 'name': ''};

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      music = MusicController(settings);
      output = {'type': 'speaker', 'name': ''};
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('allinone/media');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'audioOutput') return output;
            return null;
          });
      eq = EqualizerController(settings, music);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('allinone/media'),
            null,
          );
    });

    test('a saved preset brings back its curve and effects', () {
      eq.setBand(0, 6);
      eq.setBass(40);
      eq.saveCurrent('  Ma basse ');
      expect(eq.saved.single['name'], 'Ma basse');
      expect(eq.preset, 'Ma basse');
      eq.reset();
      expect(eq.levels.first, 0);
      eq.selectSaved(eq.saved.single);
      expect(eq.levels.first, 6);
      expect(eq.bass, 40);
      expect(eq.preset, 'Ma basse');
      // Same name replaces; blank names are refused.
      eq.saveCurrent('Ma basse');
      eq.saveCurrent('   ');
      expect(eq.saved, hasLength(1));
      // It is still there for the next launch.
      final again = EqualizerController(settings, music);
      expect(again.saved.single['name'], 'Ma basse');
      eq.deleteSaved('Ma basse');
      expect(eq.saved, isEmpty);
      expect(eq.preset, isNull);
    });

    test('each output remembers its own settings', () async {
      await eq.refreshOutput();
      expect(eq.output, 'speaker');
      expect(eq.outputLabel, 'Haut-parleur du téléphone');
      eq.setBand(1, 4);
      eq.setOutputProfile(true);

      output = {'type': 'bluetooth', 'name': 'Casque Sony'};
      await eq.refreshOutput();
      expect(eq.output, 'bluetooth:Casque Sony');
      expect(eq.outputLabel, 'Casque Sony');
      expect(eq.outputHasProfile, isFalse);
      eq.reset(); // headphones start neutral
      eq.setBand(2, -3);
      eq.setOutputProfile(true);

      // Back on the speaker: its curve returns, then the headphones' one.
      output = {'type': 'speaker', 'name': ''};
      await eq.refreshOutput();
      expect(eq.levels[1], 4);
      expect(eq.levels[2], 0);
      output = {'type': 'bluetooth', 'name': 'Casque Sony'};
      await eq.refreshOutput();
      expect(eq.levels[2], -3);

      // Changes made while a profile is bound are kept in it.
      eq.setBand(3, 2);
      output = {'type': 'speaker', 'name': ''};
      await eq.refreshOutput();
      output = {'type': 'bluetooth', 'name': 'Casque Sony'};
      await eq.refreshOutput();
      expect(eq.levels[3], 2);

      eq.setOutputProfile(false);
      expect(eq.outputHasProfile, isFalse);
    });
  });
}
