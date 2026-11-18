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
    _restoreExtras();
    _music.audioSessionId.addListener(_apply);
    _music.addListener(_onMusic);
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
      _load(jsonDecode(saved) as Map<String, dynamic>);
    } on Object {
      // Unreadable settings: keep the defaults.
    }
  }

  void _load(Map<String, dynamic> m) {
    enabled = m['enabled'] as bool;
    bands = (m['bands'] as List).cast<int>();
    levels = [for (final v in m['levels'] as List) (v as num).toDouble()];
    preset = m['preset'] as String?;
    bass = (m['bass'] as num).toDouble();
    widening = (m['widening'] as num).toDouble();
    gain = (m['gain'] as num).toDouble();
    balance = (m['balance'] as num).toDouble();
  }

  Map<String, Object?> _state() => {
    'enabled': enabled,
    'bands': bands,
    'levels': levels,
    'preset': preset,
    'bass': bass,
    'widening': widening,
    'gain': gain,
    'balance': balance,
  };

  void _save() {
    _settings.setRaw('equalizer', jsonEncode(_state()));
    final key = output;
    if (key != null && profiles.containsKey(key)) {
      // The curve of a bound output follows every change.
      profiles[key] = _state();
      _saveExtras();
    }
  }

  // ---- Personal presets ----

  /// Curves saved by the user: name, bands, levels and effects.
  List<Map<String, Object?>> saved = [];

  // ---- Per-output profiles ----

  /// What is plugged in: speaker, wired, usb or bluetooth plus its name.
  String? output;

  /// Settings remembered for an output, keyed like [output].
  Map<String, Map<String, Object?>> profiles = {};

  bool get outputHasProfile => output != null && profiles.containsKey(output);

  String get outputLabel {
    final o = output;
    if (o == null) return '';
    if (o == 'speaker') return 'Haut-parleur du téléphone';
    if (o == 'wired') return 'Casque filaire';
    if (o == 'usb') return 'Audio USB';
    return o.startsWith('bluetooth:') ? o.substring(10) : o;
  }

  void _restoreExtras() {
    try {
      final a = _settings.raw('eqSaved');
      if (a != null) {
        saved = [
          for (final m in jsonDecode(a) as List)
            Map<String, Object?>.from(m as Map),
        ];
      }
      final b = _settings.raw('eqProfiles');
      if (b != null) {
        profiles = {
          for (final e in (jsonDecode(b) as Map).entries)
            e.key as String: Map<String, Object?>.from(e.value as Map),
        };
      }
    } on Object {
      saved = [];
      profiles = {};
    }
  }

  void _saveExtras() {
    _settings.setRaw('eqSaved', jsonEncode(saved));
    _settings.setRaw('eqProfiles', jsonEncode(profiles));
  }

  /// Keeps the current curve and effects under [name] (replacing a saved
  /// curve of the same name).
  void saveCurrent(String name) {
    final n = name.trim();
    if (n.isEmpty) return;
    saved = [
      for (final m in saved)
        if (m['name'] != n) m,
      {
        'name': n,
        'bands': bands,
        'levels': levels,
        'bass': bass,
        'widening': widening,
        'gain': gain,
      },
    ];
    preset = n;
    _saveExtras();
    _changed();
  }

  void deleteSaved(String name) {
    saved = [
      for (final m in saved)
        if (m['name'] != name) m,
    ];
    if (preset == name) preset = null;
    _saveExtras();
    _changed();
  }

  void selectSaved(Map<String, Object?> m) {
    final curve = [
      for (var i = 0; i < (m['bands'] as List).length; i++)
        (
          ((m['bands'] as List)[i] as num).toDouble(),
          ((m['levels'] as List)[i] as num).toDouble(),
        ),
    ];
    levels = levelsFor(curve, bands, min: minLevel, max: maxLevel);
    bass = (m['bass'] as num).toDouble();
    widening = (m['widening'] as num).toDouble();
    gain = (m['gain'] as num).toDouble();
    preset = m['name'] as String;
    enabled = true;
    _changed();
  }

  bool _wasPlaying = false;
  void _onMusic() {
    // Headphones are (un)plugged between songs: look when playback starts.
    if (_music.playing && !_wasPlaying) refreshOutput();
    _wasPlaying = _music.playing;
  }

  /// Reads the current audio output and loads its profile, if it has one.
  Future<void> refreshOutput() async {
    final info = await MediaChannel.audioOutput();
    if (info == null) return;
    final type = info['type'] as String? ?? 'speaker';
    final name = (info['name'] as String?)?.trim() ?? '';
    final key = type == 'bluetooth' && name.isNotEmpty
        ? 'bluetooth:$name'
        : type;
    if (key == output) return;
    output = key;
    final profile = profiles[key];
    if (profile != null) {
      try {
        _load(profile);
        _settings.setRaw('equalizer', jsonEncode(_state()));
        unawaited(_apply());
      } on Object {
        profiles.remove(key);
      }
    }
    notifyListeners();
  }

  /// Remembers (or forgets) the current settings for the current output.
  void setOutputProfile(bool on) {
    final key = output;
    if (key == null) return;
    if (on) {
      profiles[key] = _state();
    } else {
      profiles.remove(key);
    }
    _saveExtras();
    notifyListeners();
  }

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
    _music.removeListener(_onMusic);
    super.dispose();
  }
}
