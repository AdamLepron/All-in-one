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

  /// Opens a PDF: handle, page count and page sizes (width, height pairs).
  static Future<({int id, int count, List<double> sizes})> pdfOpen(
    String path,
  ) async {
    final map = (await _channel.invokeMapMethod<String, Object?>('pdfOpen', {
      'path': path,
    }))!;
    return (
      id: map['id']! as int,
      count: map['count']! as int,
      sizes: (map['sizes']! as List).cast<double>(),
    );
  }

  static Future<Uint8List?> pdfRender(int id, int page, int width) =>
      _channel.invokeMethod<Uint8List>('pdfRender', {
        'id': id,
        'page': page,
        'width': width,
      });

  static Future<void> pdfClose(int id) => _quiet('pdfClose', {'id': id});

  /// Applies the sound settings to an audio session and returns what the
  /// device supports, or null off-device.
  static Future<Map<String, Object?>?> effects(
    Map<String, Object> state,
  ) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>('effects', state);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Occurrences of the phone's calendar events in a time range (epoch ms).
  static Future<List<Map<Object?, Object?>>> calendarEvents(
    int start,
    int end,
  ) async {
    try {
      return (await _channel.invokeListMethod<Map<Object?, Object?>>(
            'calendarEvents',
            {'start': start, 'end': end},
          )) ??
          const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Content shared with the app that arrived before Dart was ready. Also
  /// switches on live delivery: later shares call the handler set with
  /// [onShared].
  static Future<Map<Object?, Object?>?> takeShared() async {
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('sharedContent');
    } on MissingPluginException {
      return null;
    }
  }

  /// Handler for content shared while the app runs.
  static void onShared(void Function(Map<Object?, Object?> content) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedArrived') {
        handler((call.arguments as Map).cast<Object?, Object?>());
      }
    });
  }

  /// Exports a montage and returns the path of the file. [args] is built by
  /// the video editor project. Throws a [PlatformException] on failure.
  static Future<String> exportVideo(Map<String, Object?> args) async =>
      (await _channel.invokeMethod<String>('exportVideo', args))!;

  /// 0–100 while an export runs, -1 when unknown.
  static Future<int> exportProgress() async {
    try {
      return await _channel.invokeMethod<int>('exportProgress') ?? -1;
    } on MissingPluginException {
      return -1;
    }
  }

  static Future<void> cancelExport() => _quiet('cancelExport', const {});

  static Future<bool> hasTorch() async => await _flag('hasTorch', const {});

  /// False when the device has no flash or the camera is using it.
  static Future<bool> setTorch(bool on) => _flag('torch', {'on': on});

  /// Horizontal and vertical pixels per inch of the screen, plus the
  /// logical density, or null off-device.
  static Future<({double xdpi, double ydpi, double density})?> dpi() async {
    try {
      final m = (await _channel.invokeMapMethod<String, double>('dpi'))!;
      return (xdpi: m['xdpi']!, ydpi: m['ydpi']!, density: m['density']!);
    } on MissingPluginException {
      return null;
    }
  }

  /// Starts or stops the default alarm sound.
  static Future<void> ring(bool on) => _quiet('ring', {'on': on});

  /// Creates an alarm in the system clock app; false if none is installed.
  static Future<bool> setAlarm(int hour, int minute, String label) =>
      _flag('setAlarm', {'hour': hour, 'minute': minute, 'label': label});

  /// Device orientation as [azimuth, pitch, roll] in degrees.
  static Stream<List<double>> orientation() =>
      const EventChannel('allinone/orientation')
          .receiveBroadcastStream()
          .map((e) => (e as List).cast<double>());

  static Future<bool> _flag(String method, Map<String, Object> args) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      return false;
    }
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
