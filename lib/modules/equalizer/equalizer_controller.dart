import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../music/music_controller.dart';
import 'eq_model.dart';

/// Sound settings of the music player, saved between sessions and applied
/// to the player's audio session whenever it changes.
class EqualizerController extends ChangeNotifier {
  EqualizerController(this._settings, this._music) {
    _restore();
    _music.audioSessionId.addListener(_apply);
    _apply();
  }

  final AppSettings _settings;
  final MusicController _music;

  bool enabled = false;
  List<int> bands = defaultBands;
  double minLevel = -15;
  double maxLevel = 15;
  List<double> levels = List.filled(defaultBands.length, 0);

  /// Name of the active preset, or null for a custom curve.
  String? preset = eqPresets.first.name;
  double bass = 0;
  double widening = 0;
  double gain = 0;

  /// -1 is left only, 0 centred, 1 right only.
  double balance = 0;

  /// False when the device or Android version lacks the effect.
  bool balanceSupported = true;

  /// True once a song has played, so there is a session to act on.
  bool get attached => _music.audioSessionId.value != null;

  void _restore() {
    final saved = _settings.raw('equalizer');
    if (saved == null) return;
    try {
      final m = jsonDecode(saved) as Map<String, dynamic>;
      enabled = m['enabled'] as bool;
      bands = (m['bands'] as List).cast<int>();
      levels = [for (final v in m['levels'] as List) (v as num).toDouble()];
      preset = m['preset'] as String?;
      bass = (m['bass'] as num).toDouble();
      widening = (m['widening'] as num).toDouble();
      gain = (m['gain'] as num).toDouble();
      balance = (m['balance'] as num).toDouble();
    } on Object {
      // Unreadable settings: keep the defaults.
    }
  }

  void _save() => _settings.setRaw(
    'equalizer',
    jsonEncode({
      'enabled': enabled,
      'bands': bands,
      'levels': levels,
      'preset': preset,
      'bass': bass,
      'widening': widening,
      'gain': gain,
      'balance': balance,
    }),
  );

  Future<void> _apply() async {
    final session = _music.audioSessionId.value;
    if (session == null) return;
    final info = await MediaChannel.effects({
      'session': session,
      'enabled': enabled,
      'levels': levels,
      'bass': bass,
      'widening': widening,
      'gain': gain,
      'balance': balance,
    });
    if (info == null) return;
    balanceSupported = info['balance'] == true;
    final freqs = (info['freqs'] as List?)?.cast<int>();
    if (freqs != null && freqs.isNotEmpty) {
      minLevel = (info['min'] as num).toDouble();
      maxLevel = (info['max'] as num).toDouble();
      if (!listEquals(freqs, bands)) {
        // The device has other bands than assumed: carry the curve over.
        final curve = [
          for (var i = 0; i < bands.length; i++)
            (bands[i].toDouble(), levels[i]),
        ];
        bands = freqs;
        levels = levelsFor(curve, bands, min: minLevel, max: maxLevel);
        _save();
        unawaited(_apply());
      }
    }
    notifyListeners();
  }

  void _changed() {
    notifyListeners();
    _save();
    _apply();
  }

  void setEnabled(bool value) {
    enabled = value;
    _changed();
  }

  void setBand(int index, double db) {
    levels = [...levels]..[index] = db;
    preset = null;
    enabled = true;
    _changed();
  }

  void selectPreset(EqPreset p) {
    preset = p.name;
    levels = levelsFor(p.points, bands, min: minLevel, max: maxLevel);
    enabled = true;
    _changed();
  }

  void setBass(double v) {
    bass = v;
    enabled = true;
    _changed();
  }

  void setWidening(double v) {
    widening = v;
    enabled = true;
    _changed();
  }

  void setGain(double v) {
    gain = v;
    enabled = true;
    _changed();
  }

  void setBalance(double v) {
    // Snap to the centre so it is easy to return to.
    balance = v.abs() < 0.04 ? 0 : v;
    enabled = true;
    _changed();
  }

  void reset() {
    preset = eqPresets.first.name;
    levels = List.filled(bands.length, 0);
    bass = widening = gain = balance = 0;
    _changed();
  }

  @override
  void dispose() {
    _music.audioSessionId.removeListener(_apply);
    super.dispose();
  }
}
