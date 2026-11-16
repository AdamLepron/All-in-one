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
}
