import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/video_project.dart';
import 'package:flutter_test/flutter_test.dart';

Media video(int id, {int seconds = 20}) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/v$id',
  width: 1920,
  height: 1080,
  duration: Duration(seconds: seconds),
);

Media photo(int id) => Media(
  id: id,
  video: false,
  path: '/p/$id.jpg',
  name: 'IMG_$id.jpg',
  date: DateTime(2030, 1, 1),
  uri: 'content://media/p$id',
  width: 4000,
  height: 3000,
);

void main() {
  group('cutting a passage out', () {
    VideoProject make() => VideoProject(video(1))
      ..clips.first.startMs = 1000
      ..clips.first.endMs = 11000;

    test('the middle goes, both sides stay as two clips', () {
      final p = make();
      p.clips.first
        ..transition = TransitionKind.flash
        ..transitionMs = 1000;
      expect(p.cutOut(0, 4000, 7000), isTrue);
      expect(p.clips, hasLength(2));
      expect((p.clips[0].startMs, p.clips[0].endMs), (1000, 4000));
      expect((p.clips[1].startMs, p.clips[1].endMs), (7000, 11000));
      // The hand-over to the next clip stays at the end.
      expect(p.clips[0].transition, TransitionKind.none);
      expect(p.clips[1].transition, TransitionKind.flash);
      expect(p.clips[1].transitionMs, 1000);
      expect(p.totalMs, 7000);
    });

    test('a passage at an edge just trims', () {
      final p = make();
      expect(p.cutOut(0, 1000, 5000), isTrue); // from the start
      expect(p.clips, hasLength(1));
      expect((p.clips[0].startMs, p.clips[0].endMs), (5000, 11000));
      expect(p.cutOut(0, 9000, 11000), isTrue); // to the end
      expect((p.clips[0].startMs, p.clips[0].endMs), (5000, 9000));
    });

    test('too little left, or nothing to remove, is refused', () {
      final p = make();
      expect(p.cutOut(0, 1100, 10900), isFalse); // both sides under 0.5 s
      expect(p.cutOut(0, 5000, 5050), isFalse); // under 0.1 s
      expect(p.cutOut(0, 20000, 30000), isFalse); // outside the clip
      expect(p.clips, hasLength(1));
      expect((p.clips[0].startMs, p.clips[0].endMs), (1000, 11000));
    });

    test('pictures cannot be cut', () {
      final p = VideoProject(photo(1));
      expect(p.cutOut(0, 500, 3000), isFalse);
    });
  });

  group('image clips', () {
    test('a picture lasts a few seconds and says so to the exporter', () {
      final p = VideoProject(video(1));
      p.clips.add(VideoClip(photo(2)));
      expect(p.clips[1].isImage, isTrue);
      expect(p.clips[1].outputMs, defaultImageMs);
      expect(p.clips[1].sourceMs, maxImageMs);
      final clips = p.exportArgs('/o.mp4')['clips']! as List;
      expect((clips[1] as Map)['image'], true);
      expect((clips[0] as Map).containsKey('image'), isFalse);
    });

    test('they survive saving', () {
      final p = VideoProject(photo(1));
      p.clips.first.endMs = 7000;
      final back = VideoProject.fromJson(p.toJson());
      expect(back.clips.first.isImage, isTrue);
      expect(back.clips.first.outputMs, 7000);
    });
  });

  group('transitions', () {
    test('the old fade is the fade-to-black transition', () {
      final c = VideoClip(video(1))..fade = true;
      expect(c.transition, TransitionKind.fade);
      c.fade = false;
      expect(c.transition, TransitionKind.none);
      c.transition = TransitionKind.zoom;
      c.fade = false; // only a fade is switched off
      expect(c.transition, TransitionKind.zoom);
    });

    test('projects from before keep their fade', () {
      final p = VideoProject(video(1));
      p.clips.add(VideoClip(video(2)));
      final j = p.toJson();
      (j['clips'] as List).first
        ..['fade'] = true
        ..remove('transition');
      final back = VideoProject.fromJson(j);
      expect(back.clips.first.transition, TransitionKind.fade);
    });

    test('a slide is sent to both clips it joins', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..endMs = 10000
        ..transition = TransitionKind.slideLeft
        ..transitionMs = 1000;
      p.clips.add(VideoClip(video(2))..endMs = 10000);
      final clips = p.exportArgs('/o.mp4')['clips']! as List;
      final (a, b) = (clips[0] as Map, clips[1] as Map);
      expect(a['trOut'], TransitionKind.slideLeft.index);
      expect(a['trOutMs'], 1000);
      expect(b['trIn'], TransitionKind.slideLeft.index);
      expect(b['trInMs'], 1000);
      expect(a.containsKey('trIn'), isFalse);
      expect(b.containsKey('trOut'), isFalse);
    });

    test('the last clip only closes; a plain fade uses the fade keys', () {
      final p = VideoProject(video(1));
      p.clips.first.transition = TransitionKind.slideRight;
      var a = (p.exportArgs('/o.mp4')['clips']! as List).first as Map;
      expect(a.containsKey('trOut'), isFalse);
      p.clips.first.transition = TransitionKind.fade;
      a = (p.exportArgs('/o.mp4')['clips']! as List).first as Map;
      expect(a['fadeOutMs'], fadeMs);
      expect(a.containsKey('trOut'), isFalse);
    });

    test('a short clip shortens its transition to half its length', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..endMs = 1000
        ..transition = TransitionKind.zoom
        ..transitionMs = 1500;
      p.clips.add(VideoClip(video(2)));
      final a = (p.exportArgs('/o.mp4')['clips']! as List).first as Map;
      expect(a['trOutMs'], 500);
    });
  });

  group('preview pose', () {
    test('a slide leaves by the left and arrives from the right', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..endMs = 10000
        ..transition = TransitionKind.slideLeft
        ..transitionMs = 1000;
      p.clips.add(VideoClip(video(2))..endMs = 10000);
      expect(p.poseAt(0, 5000).isNeutral, isTrue);
      expect(p.poseAt(0, 10000).dx, closeTo(-2, 1e-9)); // gone
      expect(p.poseAt(0, 9500).dx, closeTo(-1, 1e-9)); // halfway
      expect(p.poseAt(1, 0).dx, closeTo(2, 1e-9)); // about to enter
      expect(p.poseAt(1, 1000).isNeutral, isTrue);
    });

    test('flash burns, zoom dips to black, fade goes dark', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..endMs = 10000
        ..transition = TransitionKind.flash
        ..transitionMs = 1000;
      p.clips.add(VideoClip(video(2))..endMs = 10000);
      expect(p.poseAt(0, 10000).gain, closeTo(12, 1e-9));
      p.clips.first.transition = TransitionKind.zoom;
      final z = p.poseAt(0, 10000);
      expect(z.gain, closeTo(0, 1e-9));
      expect(z.scale, closeTo(1.6, 1e-9));
      p.clips.first.transition = TransitionKind.fade;
      expect(p.poseAt(0, 9700).gain, lessThan(0.6));
      expect(p.poseAt(0, 5000).gain, 1);
    });

    test('motion effects scale over the clip', () {
      final p = VideoProject(video(1));
      p.clips.first
        ..endMs = 10000
        ..effect = ClipEffect.zoomIn;
      expect(p.poseAt(0, 0).scale, 1);
      expect(p.poseAt(0, 10000).scale, closeTo(1.25, 1e-9));
      p.clips.first.effect = ClipEffect.zoomOut;
      expect(p.poseAt(0, 10000).scale, closeTo(1, 1e-9));
    });
  });

  group('layers and sounds', () {
    test('nothing is sent when there are none', () {
      final a = VideoProject(video(1)).exportArgs('/o.mp4');
      expect(a.containsKey('overlays'), isFalse);
      expect(a.containsKey('sounds'), isFalse);
    });

    test('overlays and sounds are sent, cut at the end of the montage', () {
      final p = VideoProject(video(1));
      p.clips.first.endMs = 10000;
      p.overlays
        ..add(OverlayClip(photo(2), startMs: 8000, durationMs: 5000, track: 1))
        ..add(OverlayClip(video(3), startMs: 12000)); // starts after the end
      p.sounds.add(
        AudioClip('/s/a.mp3', 'a.mp3', startMs: 9000, durationMs: 4000),
      );
      final a = p.exportArgs('/o.mp4');
      final o = (a['overlays']! as List);
      expect(o, hasLength(1));
      expect((o.first as Map)['durationMs'], 2000);
      expect((o.first as Map)['image'], true);
      expect((o.first as Map)['track'], 1);
      expect((o.first as Map)['aspect'], closeTo(4 / 3, 1e-9));
      final s = (a['sounds']! as List).single as Map;
      expect((s['startMs'], s['durationMs'], s['volume']), (9000, 1000, 1.0));
    });

    test('they survive saving and tame bad values', () {
      final p = VideoProject(video(1));
      p.overlays.add(
        OverlayClip(
          video(2),
          startMs: 1500,
          trimStartMs: 2000,
          durationMs: 3000,
          cx: 0.3,
          cy: 0.6,
          width: 0.5,
          opacity: 0.8,
          volume: 1,
          track: 2,
        ),
      );
      p.sounds.add(
        AudioClip(
          '/s/b.m4a',
          'Voix',
          startMs: 700,
          durationMs: 2500,
          sourceMs: 9000,
          volume: 1.5,
        ),
      );
      final j = p.toJson();
      final back = VideoProject.fromJson(j);
      final o = back.overlays.single;
      expect(
        (o.startMs, o.trimStartMs, o.durationMs, o.track),
        (1500, 2000, 3000, 2),
      );
      expect(
        (o.cx, o.cy, o.width, o.opacity, o.volume),
        (0.3, 0.6, 0.5, 0.8, 1),
      );
      final s = back.sounds.single;
      expect(
        (s.name, s.startMs, s.durationMs, s.sourceMs, s.volume),
        ('Voix', 700, 2500, 9000, 1.5),
      );

      ((j['overlays'] as List).first as Map)
        ..['cx'] = 9
        ..['width'] = 0
        ..['track'] = 99
        ..['opacity'] = -1;
      final tamed = VideoProject.fromJson(j).overlays.single;
      expect(
        (tamed.cx, tamed.width, tamed.track, tamed.opacity),
        (1.0, 0.05, overlayLanes - 1, 0.1),
      );
    });

    test('limits follow the source', () {
      final o = OverlayClip(video(2, seconds: 10), trimStartMs: 4000);
      expect(o.maxDurationMs, 6000);
      expect(OverlayClip(photo(1)).maxDurationMs, maxImageMs);
      final a = AudioClip(
        '/s.mp3',
        's',
        durationMs: 3000,
        sourceMs: 8000,
        trimStartMs: 1000,
      );
      expect(a.maxDurationMs, 7000);
      expect(
        AudioClip('/s.mp3', 's', durationMs: 3000).maxDurationMs,
        greaterThan(1000000),
      );
    });

    test('a title can be placed freely and keeps it', () {
      final p = VideoProject(video(1));
      p.titles.add(TitleItem('Salut', x: 0.25, y: 0.75));
      final t = (p.exportArgs('/o.mp4')['titles']! as List).first as Map;
      expect((t['x'], t['y']), (0.25, 0.75));
      final back = VideoProject.fromJson(p.toJson()).titles.single;
      expect((back.x, back.y), (0.25, 0.75));
      p.titles.add(TitleItem('Ailleurs'));
      final u = (p.exportArgs('/o.mp4')['titles']! as List).last as Map;
      expect(u.containsKey('x'), isFalse);
    });
  });
}
