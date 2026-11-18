import 'dart:math' as math;
import 'dart:typed_data';

/// Sound level of a block of 16-bit little-endian mono samples, in dB
/// relative to the loudest possible signal (dBFS, 0 at most). Silence gives
/// [silenceFloor].
const silenceFloor = -90.0;

double dbfsOfPcm16(Uint8List bytes) {
  final samples = bytes.lengthInBytes ~/ 2;
  if (samples == 0) return silenceFloor;
  final data = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < samples; i++) {
    final v = data.getInt16(i * 2, Endian.little) / 32768.0;
    sum += v * v;
  }
  final rms = math.sqrt(sum / samples);
  if (rms <= 0) return silenceFloor;
  return math.max(silenceFloor, 20 * math.log(rms) / math.ln10);
}

/// Phone microphones are not calibrated: this offset turns dBFS into a
/// figure close to a sound-level meter's dB(A) for most phones, and the
/// user can adjust it against a known reference.
const defaultCalibration = 90.0;

/// Sound level shown to the user, in dB, kept within a plausible range.
double dbFromDbfs(double dbfs, {double calibration = defaultCalibration}) =>
    (dbfs + calibration).clamp(0.0, 130.0);

/// How loud a level feels.
String describeLevel(double db) {
  if (db < 30) return 'Très calme';
  if (db < 45) return 'Calme';
  if (db < 60) return 'Conversation';
  if (db < 75) return 'Animé';
  if (db < 85) return 'Bruyant';
  if (db < 100) return 'Très bruyant : risque pour l\'ouïe';
  return 'Dangereux';
}

/// Minimum, maximum and average of the levels heard since a reset. The
/// average is an energy average (as sound meters do), not of the dB values.
class SoundStats {
  double? _min;
  double? _max;
  double _energy = 0;
  int _count = 0;

  void add(double db) {
    _min = _min == null ? db : math.min(_min!, db);
    _max = _max == null ? db : math.max(_max!, db);
    _energy += math.pow(10, db / 10);
    _count++;
  }

  double? get min => _min;
  double? get max => _max;
  int get count => _count;

  double? get average =>
      _count == 0 ? null : 10 * math.log(_energy / _count) / math.ln10;

  void reset() {
    _min = _max = null;
    _energy = 0;
    _count = 0;
  }
}

/// Smooths a stream of levels: rises quickly, falls slowly, like the needle
/// of a meter, so the figure stays readable.
class LevelSmoother {
  LevelSmoother({this.rise = 0.6, this.fall = 0.15});
  final double rise;
  final double fall;
  double? _value;

  double add(double db) {
    final v = _value;
    if (v == null) return _value = db;
    final k = db > v ? rise : fall;
    return _value = v + (db - v) * k;
  }
}
