import 'dart:ui';

import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/video_project.dart';
import 'package:flutter_test/flutter_test.dart';

Media video(int id, {int seconds = 60, int w = 1920, int h = 1080}) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2026),
  uri: 'content://media/external/video/media/$id',
  width: w,
  height: h,
  duration: Duration(seconds: seconds),
);

void main() {
  test('a new clip covers the whole video', () {
    final c = Clip(video(1, seconds: 90));
    expect((c.startMs, c.endMs), (0, 90000));
    expect(c.keptMs, 90000);
    expect(c.outputMs, 90000);
  });

  test('trimming never crosses or leaves the video', () {
    final c = Clip(video(1, seconds: 10));
    c.setStart(4000);
    c.setEnd(7000);
    expect((c.startMs, c.endMs), (4000, 7000));
    c.setStart(9000); // past the end: stops at the minimum length
    expect(c.startMs, 7000 - minClipMs);
    c.setStart(-5);
    expect(c.startMs, 0);
    c.setEnd(99999);
    expect(c.endMs, 10000);
    c.setEnd(0);
    expect(c.endMs, c.startMs + minClipMs);
  });

  test('speed changes the output length', () {
    final c = Clip(video(1, seconds: 10))..setStart(2000);
    expect(c.keptMs, 8000);
    c.speed = 2;
    expect(c.outputMs, 4000);
    c.speed = 0.5;
    expect(c.outputMs, 16000);
    c.speed = 3;
    expect(c.outputMs, 2667);
  });

  test('rotation turns clockwise and swaps the frame', () {
    final c = Clip(video(1, w: 1920, h: 1080));
    expect(c.orientedSize, const Size(1920, 1080));
    c.rotateClockwise();
    expect((c.rotation, c.orientedSize), (90, const Size(1080, 1920)));
    c.rotateClockwise();
    expect(c.orientedSize, const Size(1920, 1080));
    c
      ..rotateClockwise()
      ..rotateClockwise();
    expect(c.rotation, 0);
    // A displayed size from the player wins over the stored one.
    c.shownSize = const Size(1080, 1920);
    expect(c.orientedSize, const Size(1080, 1920));
  });

  test('project total, order and copies', () {
    final p = VideoProject(video(1, seconds: 10));
    p.clips.add(Clip(video(2, seconds: 20))..speed = 2);
    p.clips.add(Clip(video(3, seconds: 5)));
    expect(p.totalMs, 10000 + 10000 + 5000);
    p.move(2, 0);
    expect(p.clips.map((c) => c.media.id), [3, 1, 2]);
    p.move(0, 3); // dropped after the last
    expect(p.clips.map((c) => c.media.id), [1, 2, 3]);
    p.move(2, 1);
    expect(p.clips.map((c) => c.media.id), [1, 3, 2]);
    final copy = p.clips[2].copy();
    expect(copy.speed, 2);
    copy.speed = 1;
    expect(p.clips[2].speed, 2); // independent
  });

  test('export size is even, follows the first clip and is capped', () {
    expect(
      VideoProject(video(1, w: 1920, h: 1080)).outputSize,
      const Size(1920, 1080),
    );
    expect(
      VideoProject(video(1, w: 3840, h: 2160)).outputSize,
      const Size(1920, 1080),
    );
    expect(
      VideoProject(video(1, w: 1080, h: 1920)).outputSize,
      const Size(1080, 1920),
    );
    final odd = VideoProject(video(1, w: 1279, h: 719)).outputSize;
    expect(odd.width % 2, 0);
    expect(odd.height % 2, 0);
    final p = VideoProject(video(1, w: 1920, h: 1080));
    p.clips.first.rotateClockwise();
    expect(p.outputSize, const Size(1080, 1920));
    // Unknown dimensions fall back to a standard frame.
    expect(
      VideoProject(video(1, w: 0, h: 0)).outputSize,
      const Size(1280, 720),
    );
  });

  test('validation', () {
    final p = VideoProject(video(1, seconds: 10));
    expect(p.problem, isNull);
    p.clips.first.startMs = 9800; // bypassing the setters
    expect(p.problem, 'Un extrait est trop court');
    p.clips.clear();
    expect(p.problem, 'Ajoutez au moins une vidéo');
    final long = VideoProject(video(1, seconds: 5 * 3600));
    expect(long.problem, 'Le montage dépasse 4 heures');
  });

  test('export arguments', () {
    final p = VideoProject(video(1, seconds: 30))
      ..muteOriginal = true
      ..musicPath = '/musique.mp3';
    p.clips.first
      ..setStart(1000)
      ..setEnd(9000)
      ..speed = 1.5
      ..rotateClockwise();
    final args = p.exportArgs('/sortie.mp4');
    expect(args['output'], '/sortie.mp4');
    expect((args['width'], args['height']), (1080, 1920));
    expect(args['muteOriginal'], true);
    expect(args['music'], '/musique.mp3');
    expect((args['clips']! as List).single, {
      'uri': 'content://media/external/video/media/1',
      'startMs': 1000,
      'endMs': 9000,
      'speed': 1.5,
      'rotation': 90,
    });
  });

  test('clock format', () {
    expect(clock(0), '0:00,0');
    expect(clock(3400), '0:03,4');
    expect(clock(62000), '1:02,0');
    expect(clock(3599999), '60:00,0');
  });
}
