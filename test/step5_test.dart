import 'dart:io';

import 'package:all_in_one/modules/clock/clock_controller.dart';
import 'package:all_in_one/modules/clock/world_cities.dart';
import 'package:all_in_one/modules/qr/qr_content.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/sensors/sensors_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('QR content is classified and Wi-Fi codes round-trip', () {
    expect(QrContent('https://example.org/a?b=1').kind, QrKind.url);
    expect(QrContent('example.org').kind, QrKind.text);
    expect(QrContent('javascript:alert(1)').kind, QrKind.text);
    expect(QrContent('tel:+33123456789').display, '+33123456789');
    expect(QrContent('mailto:a@b.fr?subject=x').display, 'a@b.fr');

    final code = wifiCode('Maison; 5G', r'p:a\ss;word');
    final parsed = QrContent(code);
    expect(parsed.kind, QrKind.wifi);
    expect(parsed.wifiName, 'Maison; 5G');
    expect(parsed.wifiPassword, r'p:a\ss;word');
    expect(wifiCode('Libre', ''), 'WIFI:S:Libre;T:nopass;;');
  });

  test('clock formatting', () {
    expect(formatCountdown(const Duration(minutes: 5)), '05:00');
    expect(formatCountdown(const Duration(milliseconds: 1)), '00:01');
    expect(formatCountdown(Duration.zero), '00:00');
    expect(formatCountdown(const Duration(hours: 1, minutes: 5)), '1:05:00');
    expect(formatStopwatch(const Duration(milliseconds: 83450)), '01:23,45');
    expect(
      formatStopwatch(const Duration(hours: 1, milliseconds: 10)),
      '1:00:00,01',
    );
    expect(offsetLabel(Duration.zero), 'Même heure');
    expect(offsetLabel(const Duration(hours: 6)), '+6 h');
    expect(offsetLabel(const Duration(hours: -4, minutes: -30)), '−4 h 30');
  });

  test('world clock follows daylight saving time', () {
    for (final (_, zone) in worldCities) {
      expect(() => timeIn(zone, DateTime.now()), returnsNormally, reason: zone);
    }
    // Tokyo is 8 h ahead of Paris in winter and 7 h in summer.
    final winter = DateTime.utc(2026, 1, 15, 12);
    final summer = DateTime.utc(2026, 7, 15, 12);
    Duration gap(DateTime t) =>
        timeIn('Asia/Tokyo', t).time.difference(timeIn('Europe/Paris', t).time);
    expect(gap(winter), const Duration(hours: 8));
    expect(gap(summer), const Duration(hours: 7));
  });

  test('countdown and stopwatch state', () {
    final clock = ClockController();
    expect(clock.timerIdle, true);
    clock.setTimer(const Duration(minutes: 2));
    clock.startTimer();
    expect(clock.timerRunning, true);
    clock.setTimer(const Duration(minutes: 9)); // ignored while running
    expect(clock.timerTotal, const Duration(minutes: 2));
    clock.addMinute();
    expect(clock.timerTotal, const Duration(minutes: 3));
    expect(clock.remaining.inSeconds, inInclusiveRange(178, 180));
    clock.pauseTimer();
    expect(clock.timerPaused, true);
    clock.resetTimer();
    expect(clock.timerIdle, true);
    expect(clock.remaining, const Duration(minutes: 3));

    clock.toggleWatch();
    clock.lap();
    expect(clock.laps.length, 1);
    clock.resetWatch();
    expect(clock.laps, isEmpty);
    expect(clock.elapsed, Duration.zero);
    clock.dispose();
  });

  test('compass headings', () {
    expect(cardinal(0), 'N');
    expect(cardinal(359), 'N');
    expect(cardinal(44), 'NE');
    expect(cardinal(180), 'S');
    expect(cardinal(270), 'O');
  });

  test('recordings can be listed, renamed and deleted', () async {
    final tmp = await Directory.systemTemp.createTemp('rec_test');
    addTearDown(() => tmp.delete(recursive: true));
    await File('${tmp.path}/Mémo.m4a').writeAsString('x' * 1000);
    await File('${tmp.path}/index.json').writeAsString('{"Mémo.m4a": 4200}');
    final recorder = RecorderController(directory: () async => tmp.path);
    await recorder.load();
    expect(recorder.recordings.single.name, 'Mémo');
    expect(
      recorder.recordings.single.duration,
      const Duration(milliseconds: 4200),
    );

    expect(await recorder.rename(recorder.recordings.single, 'Réunion'), true);
    expect(recorder.recordings.single.name, 'Réunion');
    expect(
      recorder.recordings.single.duration,
      const Duration(milliseconds: 4200),
    );

    await File('${tmp.path}/Autre.m4a').writeAsString('y');
    await recorder.load();
    final other = recorder.recordings.firstWhere((r) => r.name == 'Autre');
    expect(await recorder.rename(other, 'Réunion'), false); // name taken
    await recorder.delete(other);
    expect(recorder.recordings.map((r) => r.name), ['Réunion']);
    recorder.dispose();
  });
}
