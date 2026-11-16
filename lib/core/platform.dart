import 'package:flutter/services.dart';

/// Bridge to the native Android code in MainActivity.
class MediaChannel {
  static const _channel = MethodChannel('allinone/media');

  static Future<List<Map<Object?, Object?>>> songs() async =>
      (await _channel.invokeListMethod<Map<Object?, Object?>>('songs')) ??
      const [];

  static Future<Uint8List?> artwork(int songId, int albumId, int size) =>
      _channel.invokeMethod<Uint8List>('artwork', {
        'songId': songId,
        'albumId': albumId,
        'size': size,
      });

  /// Total and free bytes of internal storage, or null when unavailable.
  static Future<({int total, int free})?> storage() async {
    try {
      final map = await _channel.invokeMapMethod<String, int>('storage');
      if (map == null) return null;
      return (total: map['total']!, free: map['free']!);
    } on MissingPluginException {
      return null;
    }
  }

  /// Photos and videos known to the device.
  static Future<List<Map<Object?, Object?>>> media() async =>
      (await _channel.invokeListMethod<Map<Object?, Object?>>('media')) ??
      const [];

  static Future<Uint8List?> thumbnail(
    int id, {
    required bool video,
    int size = 256,
  }) => _channel.invokeMethod<Uint8List>('thumbnail', {
    'id': id,
    'video': video,
    'size': size,
  });

  /// Tells Android that files at [paths] were added, moved or removed.
  static Future<void> scan(List<String> paths) =>
      _quiet('scan', {'paths': paths});

  /// Rescans restored files and gives Android a moment to index them.
  static Future<void> rescan(List<String> paths) async {
    await scan(paths);
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  static Future<double> brightness() async =>
      await _value('getBrightness') ?? 0.5;

  /// 0–1, or a negative value to follow the system setting again.
  static Future<void> setBrightness(double value) =>
      _quiet('setBrightness', {'value': value});

  static Future<double> volume() async => await _value('getVolume') ?? 0.5;

  static Future<void> setVolume(double value) =>
      _quiet('setVolume', {'value': value});

  static Future<void> keepScreenOn(bool on) =>
      _quiet('keepScreenOn', {'on': on});

  static Future<double?> _value(String method) async {
    try {
      return await _channel.invokeMethod<double>(method);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> _quiet(String method, Map<String, Object> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not on a device (tests).
    }
  }
}
