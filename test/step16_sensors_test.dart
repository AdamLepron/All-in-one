import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/modules/sensors/sound_level.dart';
import 'package:all_in_one/modules/sensors/sound_meter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 16-bit mono block: a sine wave of [amplitude] (0–1 of full scale).
Uint8List tone(double amplitude, {int samples = 800}) {
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    final v = (math.sin(2 * math.pi * i / 40) * amplitude * 32767).round();
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('level maths', () {
    test('silence, full scale and halves', () {
      expect(dbfsOfPcm16(Uint8List(0)), silenceFloor);
      expect(dbfsOfPcm16(Uint8List(1600)), silenceFloor); // zeros
      // A full-scale sine has an RMS of 1/√2: about −3 dBFS.
      expect(dbfsOfPcm16(tone(1)), closeTo(-3.01, 0.05));
      // Halving the amplitude lowers the level by 6 dB.
      expect(dbfsOfPcm16(tone(0.5)), closeTo(-9.03, 0.05));
      expect(dbfsOfPcm16(tone(0.05)), closeTo(-29.0, 0.1));
    });

    test('an odd trailing byte is ignored', () {
      final even = tone(0.5, samples: 100);
      final odd = Uint8List.fromList([...even, 7]);
      expect(dbfsOfPcm16(odd), closeTo(dbfsOfPcm16(even), 1e-9));
    });

    test('calibration shifts the level and stays in range', () {
      expect(dbFromDbfs(-30), 60);
      expect(dbFromDbfs(-30, calibration: 100), 70);
      expect(dbFromDbfs(-120), 0);
      expect(dbFromDbfs(30, calibration: 110), 130);
    });

    test('descriptions follow the level', () {
      expect(describeLevel(20), 'Très calme');
      expect(describeLevel(50), 'Conversation');
      expect(describeLevel(80), 'Bruyant');
      expect(describeLevel(90), contains('ouïe'));
      expect(describeLevel(110), 'Dangereux');
    });
  });

  group('statistics', () {
    test('min, max and an energy average', () {
      final s = SoundStats();
      expect((s.min, s.max, s.average), (null, null, null));
      s.add(50);
      s.add(60);
      s.add(70);
      expect((s.min, s.max, s.count), (50, 70, 3));
      // Energy mean of 50, 60, 70 dB is well above the plain 60 dB mean.
      expect(s.average, closeTo(65.7, 0.1));
      s.reset();
      expect((s.min, s.average, s.count), (null, null, 0));
    });

    test('the smoother rises fast and falls slowly', () {
      final sm = LevelSmoother();
      expect(sm.add(40), 40);
      final up = sm.add(80); // jumps most of the way
      expect(up, greaterThan(60));
      final down = sm.add(40); // drops only partly
      expect(down, greaterThan(up - (up - 40) * 0.5));
      expect(down, lessThan(up));
    });
  });

  testWidgets('the meter shows the level of what it hears, pauses and resets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    final controller = StreamController<Uint8List>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(body: SoundMeter(source: controller.stream)),
        ),
      ),
    );
    await tester.pump();

    // About −35 dBFS with the default calibration is 55 dB: a conversation.
    for (var i = 0; i < 12; i++) {
      controller.add(tone(0.025));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Min'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    controller.add(tone(1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Conversation'), findsOneWidget); // paused: unchanged
    await tester.tap(find.text('Reprendre'));
    await tester.pump();

    await tester.tap(find.text('Remettre à zéro'));
    await tester.pump();
    expect(find.text('—'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
