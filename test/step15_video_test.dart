import 'dart:io';

import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/project_store.dart';
import 'package:all_in_one/modules/video_editor/video_project.dart';
import 'package:flutter_test/flutter_test.dart';

Media video(int id, {int seconds = 20}) => Media(
  id: id,
  video: true,
  path: '/v/clip$id.mp4',
  name: 'clip$id.mp4',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/$id',
  width: 1920,
  height: 1080,
  duration: Duration(seconds: seconds),
);

void main() {
  group('splitting', () {
    test('cuts a clip in two at a source moment', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..startMs = 2000
        ..endMs = 12000
        ..speed = 2
        ..volume = 0.5
        ..fade = true;
      expect(p.split(0, 6000), isTrue);
      expect(p.clips, hasLength(2));
      final (a, b) = (p.clips[0], p.clips[1]);
      expect((a.startMs, a.endMs), (2000, 6000));
      expect((b.startMs, b.endMs), (6000, 12000));
      // Settings are kept on both parts; the closing fade stays at the end.
      expect((a.speed, b.speed, a.volume, b.volume), (2, 2, 0.5, 0.5));
      expect((a.fade, b.fade), (false, true));
      // The total length did not change.
      expect(p.totalMs, 5000);
    });

    test('refuses a cut too close to the edges', () {
      final p = VideoProject(video(1));
      expect(p.split(0, 100), isFalse);
      expect(p.split(0, 20000 - 100), isFalse);
      expect(p.clips, hasLength(1));
      expect(p.split(0, minClipMs), isTrue); // exactly the minimum on one side
    });

    test('where each clip starts in the finished video', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..startMs = 0
        ..endMs = 10000;
      p.clips.add(
        VideoClip(video(2), startMs: 0, endMs: 4000, speed: 2),
      ); // 2 s
      p.clips.add(VideoClip(video(3), startMs: 0, endMs: 6000));
      expect(p.startOf(0), 0);
      expect(p.startOf(1), 10000);
      expect(p.startOf(2), 12000);
      expect(p.totalMs, 18000);
    });
  });

  group('export arguments', () {
    test('volume, fades and titles reach the exporter', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..startMs = 0
        ..endMs = 10000
        ..volume = 1.5
        ..fade = true;
      p.clips.add(VideoClip(video(2), startMs: 0, endMs: 10000));
      p.openingFade = true;
      p.musicVolume = 0.3;
      p.titles
        ..add(
          TitleItem(
            'Bonjour',
            startMs: 1000,
            endMs: 4000,
            place: TitlePlace.top,
            size: 0.09,
            color: 0xFFFF0000,
          ),
        )
        ..add(TitleItem('   ')) // blank: left out
        ..add(
          TitleItem('Après la fin', startMs: 30000, endMs: 33000),
        ); // beyond the video
      final args = p.exportArgs('/out.mp4');
      final clips = args['clips']! as List;
      final c0 = clips[0] as Map;
      final c1 = clips[1] as Map;
      expect(c0['volume'], 1.5);
      expect(c0['fadeInMs'], fadeMs); // opening fade
      expect(c0['fadeOutMs'], fadeMs); // fade after this clip
      expect(c1['fadeInMs'], fadeMs); // …comes back in on the next
      expect(c1['fadeOutMs'], 0);
      expect(args['musicVolume'], 0.3);
      final titles = args['titles']! as List;
      expect(titles, hasLength(1));
      final t = titles.single as Map;
      expect(
        (t['text'], t['startMs'], t['endMs'], t['place']),
        ('Bonjour', 1000, 4000, 0),
      );
    });

    test('a fade is never longer than half of a short clip', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..startMs = 0
        ..endMs = 800
        ..fade = true;
      p.openingFade = true;
      final c = (p.exportArgs('/o.mp4')['clips']! as List).single as Map;
      expect(c['fadeInMs'], 400);
      expect(c['fadeOutMs'], 400);
    });

    test('a title ending after the video is cut at its end', () {
      final p = VideoProject(video(1, seconds: 10));
      p.titles.add(TitleItem('Fin', startMs: 8000, endMs: 20000));
      final t = (p.exportArgs('/o.mp4')['titles']! as List).single as Map;
      expect(t['endMs'], 10000);
    });
  });

  group('saved projects', () {
    late Directory tmp;
    late ProjectStore store;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('step15_projects');
      store = ProjectStore(directory: () async => '${tmp.path}/p');
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    VideoProject sample() {
      final p = VideoProject(video(1));
      p.clips.first
        ..startMs = 1500
        ..endMs = 9000
        ..speed = 1.5
        ..rotation = 90
        ..volume = 0.8
        ..fade = true;
      p.clips.add(VideoClip(video(2)));
      p
        ..muteOriginal = true
        ..musicPath = '/m/song.mp3'
        ..musicName = 'song.mp3'
        ..musicVolume = 0.4
        ..openingFade = true
        ..name = 'Vacances';
      p.titles.add(
        TitleItem(
          'Plage',
          startMs: 500,
          endMs: 2500,
          place: TitlePlace.middle,
          size: 0.04,
          color: 0xFF0A84FF,
        ),
      );
      return p;
    }

    test('a project survives a round trip through JSON', () {
      final back = VideoProject.fromJson(sample().toJson());
      expect(back.name, 'Vacances');
      expect(back.clips, hasLength(2));
      final c = back.clips.first;
      expect(
        (c.startMs, c.endMs, c.speed, c.rotation, c.volume, c.fade),
        (1500, 9000, 1.5, 90, 0.8, true),
      );
      expect(c.media.uri, 'content://media/1');
      expect(c.media.duration, const Duration(seconds: 20));
      expect(
        (back.muteOriginal, back.musicPath, back.musicVolume, back.openingFade),
        (true, '/m/song.mp3', 0.4, true),
      );
      final t = back.titles.single;
      expect(
        (t.text, t.place, t.size, t.color),
        ('Plage', TitlePlace.middle, 0.04, 0xFF0A84FF),
      );
      expect(back.totalMs, sample().totalMs);
    });

    test('older or incomplete projects still load with defaults', () {
      final json = sample().toJson();
      for (final c in json['clips']! as List) {
        (c as Map<String, Object?>)
          ..remove('volume')
          ..remove('fade')
          ..remove('transition');
      }
      json
        ..remove('titles')
        ..remove('musicVolume')
        ..remove('openingFade');
      final back = VideoProject.fromJson(json);
      expect(back.clips.first.volume, 1);
      expect(back.clips.first.fade, isFalse);
      expect(back.titles, isEmpty);
      expect(back.musicVolume, 1);
      expect(
        () => VideoProject.fromJson({...json, 'clips': <Object>[]}),
        throwsFormatException,
      );
    });

    test(
      'store: save, list newest first, replace, delete, skip damage',
      () async {
        final a = sample()..name = 'A';
        final b = VideoProject(video(3))..name = 'B';
        await store.save(a, now: DateTime(2030, 1, 1));
        await store.save(b, now: DateTime(2030, 1, 2));
        expect((await store.list()).map((s) => s.project.name), ['B', 'A']);

        // Saving again replaces, and moves it to the top.
        a.name = 'A2';
        await store.save(a, now: DateTime(2030, 1, 3));
        final list = await store.list();
        expect(list.map((s) => s.project.name), ['A2', 'B']);
        expect(list.first.saved, DateTime(2030, 1, 3));

        File('${tmp.path}/p/broken.json').writeAsStringSync('{oops');
        expect(await store.list(), hasLength(2));

        await store.delete(a.id);
        expect((await store.list()).single.project.name, 'B');
        await store.delete('does-not-exist');
      },
    );

    test('quick saves end with the last one', () async {
      final p = sample();
      final writes = <Future<void>>[];
      for (var i = 1; i <= 5; i++) {
        p.name = 'v$i';
        writes.add(store.save(p, now: DateTime(2030, 1, i)));
      }
      await Future.wait(writes);
      expect((await store.list()).single.project.name, 'v5');
    });

    test('an empty folder or none at all lists nothing', () async {
      expect(
        await ProjectStore(directory: () async => '${tmp.path}/none').list(),
        isEmpty,
      );
    });
  });
}
