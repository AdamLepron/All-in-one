import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/timeline_player.dart';
import 'package:all_in_one/modules/video_editor/video_project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

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
  width: 400,
  height: 300,
);

void main() {
  group('locating a moment', () {
    VideoProject make() {
      final p = VideoProject(video(1));
      p.clips.first.endMs = 10000; // 10 s
      p.clips.add(VideoClip(video(2), endMs: 8000)..speed = 2); // 4 s
      p.clips.add(VideoClip(photo(3))); // 4 s
      return p;
    }

    test('finds the clip and the offset inside it', () {
      final p = make();
      expect(p.totalMs, 18000);
      expect(p.locate(0), (0, 0));
      expect(p.locate(9999), (0, 9999));
      expect(p.locate(10000), (1, 0));
      expect(p.locate(12500), (1, 2500));
      expect(p.locate(14000), (2, 0));
      // The very end belongs to the last clip, never past it.
      expect(p.locate(18000), (2, 4000));
      expect(p.locate(99999), (2, 4000));
      expect(p.locate(-5), (0, 0));
    });

    test('splitAtTime cuts in source time, whatever the speed', () {
      final p = make();
      // 1 s into the double-speed clip is 2 s of its source.
      expect(p.splitAtTime(11000), 2);
      expect(p.clips, hasLength(4));
      expect(p.clips[1].endMs, 2000);
      expect(p.clips[2].startMs, 2000);
      expect(p.totalMs, 18000);
      // Too close to an edge: refused.
      expect(p.splitAtTime(10100), isNull);
    });

    test('replaceWith copies a montage in place', () {
      final p = make();
      final other = VideoProject(video(9));
      other.name = 'Autre';
      other.aspect = Aspect.tall;
      other.titles.add(TitleItem('Salut'));
      p.replaceWith(other);
      expect(p.clips, hasLength(1));
      expect((p.name, p.aspect, p.titles.length), ('Autre', Aspect.tall, 1));
      expect(p.id, isNot(other.id)); // identity stays
    });
  });

  group('the clock', () {
    late int now;
    late int opened;
    late TimelinePlayer player;

    Future<VideoPlayerController?> noPreview(VideoClip clip) async {
      opened++;
      return null;
    }

    VideoProject project() {
      final p = VideoProject(video(1));
      p.clips.first.endMs = 5000;
      p.clips.add(VideoClip(video(2), endMs: 4000));
      return p;
    }

    setUp(() {
      now = 0;
      opened = 0;
    });

    TimelinePlayer make(VideoProject p) => player = TimelinePlayer(
      p,
      opener: noPreview,
      sounds: false,
      clockMs: () => now,
    );

    tearDown(() => player.dispose());

    test('seeking sets the time and opens the clip there', () async {
      final p = project();
      make(p);
      await player.start();
      expect(opened, 1);
      expect(player.clipIndex, 0);
      await player.seek(6000);
      expect(player.time.value, 6000);
      expect(player.clipIndex, 1);
      expect(opened, 2);
      expect(player.failed, isTrue); // no preview, but it still runs
      await player.seek(99999);
      expect(player.time.value, p.totalMs); // clamped
    });

    test('playing advances with the clock, crosses clips and stops', () async {
      final p = project(); // 5 s + 4 s
      make(p);
      await player.start();
      await player.play();
      expect(player.playing, isTrue);
      now = 2000;
      player.debugTick();
      expect(player.time.value, 2000);
      now = 6500;
      player.debugTick();
      expect(player.time.value, 6500);
      await Future<void>.delayed(Duration.zero);
      expect(player.clipIndex, 1);
      now = 9000; // the end
      player.debugTick();
      expect(player.time.value, 9000);
      expect(player.playing, isFalse);
      // Playing again from the end starts over.
      now = 20000;
      await player.play();
      expect(player.time.value, 0);
      player.pause();
    });

    test('pausing keeps the time; playing carries on from there', () async {
      make(project());
      await player.start();
      await player.play();
      now = 1500;
      player.debugTick();
      player.pause();
      now = 8000; // time passes while paused
      player.debugTick();
      expect(player.time.value, 1500);
      await player.play();
      now = 8500;
      player.debugTick();
      expect(player.time.value, 2000);
      player.pause();
    });

    test('the two halves of a cut share one player', () async {
      final p = VideoProject(video(1));
      p.clips.first.endMs = 10000;
      make(p);
      await player.start();
      expect(opened, 1);
      p.splitAtTime(4000);
      await player.projectChanged();
      await player.seek(7000); // second half, same file
      expect(player.clipIndex, 1);
      expect(opened, 1); // not opened again
    });

    test(
      'a picture needs no player; deleting clips keeps the playhead valid',
      () async {
        final p = project();
        p.clips.add(VideoClip(photo(3)));
        make(p);
        await player.start();
        await player.seek(10000); // inside the picture (9–13 s)
        expect(player.clipIndex, 2);
        expect(player.failed, isFalse);
        expect(opened, 1);
        p.clips.removeLast();
        p.clips.removeLast();
        await player.projectChanged();
        expect(player.time.value, p.totalMs);
        expect(player.clipIndex, 0);
      },
    );

    test('editing while playing keeps the clock coherent', () async {
      final p = project();
      make(p);
      await player.start();
      await player.play();
      now = 3000;
      player.debugTick();
      p.clips.first.speed = 2; // 5 s -> 2.5 s
      await player.projectChanged();
      now = 4000; // one more second at the new setting
      player.debugTick();
      expect(player.time.value, 4000);
      expect(player.clipIndex, 1); // already past the shortened first clip
      player.pause();
    });
  });
}
