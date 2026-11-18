import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent colours offered in the settings screen.
const accentChoices = <Color>[
  Color(0xFF5B5BD6), // indigo
  Color(0xFF1DB954), // green
  Color(0xFF0A84FF), // blue
  Color(0xFFE5484D), // red
  Color(0xFFF76B15), // orange
  Color(0xFFD6409F), // pink
  Color(0xFF12A594), // teal
];

/// Names of [accentChoices], for screen readers.
const accentNames = <String>[
  'indigo',
  'verte',
  'bleue',
  'rouge',
  'orange',
  'rose',
  'turquoise',
];

const defaultPinned = [
  'notes',
  'calculator',
  'converter',
  'music',
  'gallery',
  'files',
];

/// User preferences, persisted with shared_preferences.
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async =>
      AppSettings(await SharedPreferences.getInstance());

  ThemeMode get themeMode =>
      ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
  set themeMode(ThemeMode mode) =>
      _set(() => _prefs.setInt('themeMode', mode.index));

  /// Pure black backgrounds in dark mode.
  bool get amoled => _prefs.getBool('amoled') ?? false;
  set amoled(bool v) => _set(() => _prefs.setBool('amoled', v));

  int get accentIndex =>
      (_prefs.getInt('accent') ?? 0).clamp(0, accentChoices.length - 1);
  set accentIndex(int i) => _set(() => _prefs.setInt('accent', i));
  Color get accent => accentChoices[accentIndex];

  bool get notesGrid => _prefs.getBool('notesGrid') ?? true;
  set notesGrid(bool v) => _set(() => _prefs.setBool('notesGrid', v));

  List<String> get pinned => _prefs.getStringList('pinned') ?? defaultPinned;
  bool isPinned(String id) => pinned.contains(id);
  void togglePinned(String id) {
    final list = [...pinned];
    list.contains(id) ? list.remove(id) : list.add(id);
    _set(() => _prefs.setStringList('pinned', list));
  }

  List<String> get calcHistory =>
      _prefs.getStringList('calcHistory') ?? const [];
  void addCalcHistory(String entry) {
    final list = [entry, ...calcHistory];
    _set(() => _prefs.setStringList('calcHistory', list.take(50).toList()));
  }

  void clearCalcHistory() => _set(() => _prefs.remove('calcHistory'));

  // File manager
  bool get filesShowHidden => _prefs.getBool('filesShowHidden') ?? false;
  set filesShowHidden(bool v) =>
      _set(() => _prefs.setBool('filesShowHidden', v));

  /// Index into SortBy.values.
  int get filesSort => (_prefs.getInt('filesSort') ?? 0).clamp(0, 2);
  set filesSort(int v) => _set(() => _prefs.setInt('filesSort', v));

  bool get filesAscending => _prefs.getBool('filesAscending') ?? true;
  set filesAscending(bool v) => _set(() => _prefs.setBool('filesAscending', v));

  // Music
  Set<int> get favoriteSongs =>
      (_prefs.getStringList('favoriteSongs') ?? const [])
          .map(int.parse)
          .toSet();
  bool isFavorite(int songId) => favoriteSongs.contains(songId);
  void toggleFavorite(int songId) {
    final set = favoriteSongs;
    if (!set.remove(songId)) set.add(songId);
    _set(
      () =>
          _prefs.setStringList('favoriteSongs', [for (final id in set) '$id']),
    );
  }

  /// Most recently played first.
  List<int> get recentSongs =>
      (_prefs.getStringList('recentSongs') ?? const []).map(int.parse).toList();
  void addRecentSong(int songId) {
    final list = [songId, ...recentSongs.where((id) => id != songId)];
    _set(
      () => _prefs.setStringList('recentSongs', [
        for (final id in list.take(30)) '$id',
      ]),
    );
  }

  int get musicSort => (_prefs.getInt('musicSort') ?? 0).clamp(0, 2);
  set musicSort(int v) => _set(() => _prefs.setInt('musicSort', v));

  // Gallery and video
  int get galleryColumns => (_prefs.getInt('galleryColumns') ?? 4).clamp(2, 7);
  set galleryColumns(int v) => _set(() => _prefs.setInt('galleryColumns', v));

  Set<String> get favoriteMedia =>
      (_prefs.getStringList('favoriteMedia') ?? const []).toSet();
  bool isFavoriteMedia(String key) => favoriteMedia.contains(key);
  void toggleFavoriteMedia(String key) {
    final set = favoriteMedia;
    if (!set.remove(key)) set.add(key);
    _set(() => _prefs.setStringList('favoriteMedia', set.toList()));
  }

  /// Where each video was left, as "key:milliseconds", most recent first.
  List<String> get _videoPositions =>
      _prefs.getStringList('videoPositions') ?? const [];

  Duration videoPosition(String key) {
    for (final entry in _videoPositions) {
      if (entry.startsWith('$key:')) {
        return Duration(
          milliseconds: int.parse(entry.substring(key.length + 1)),
        );
      }
    }
    return Duration.zero;
  }

  /// Key of the video watched last, if it was not finished.
  String? get lastVideoKey =>
      _videoPositions.isEmpty ? null : _videoPositions.first.split(':').first;

  /// Remembers [position]; pass [Duration.zero] once the video is finished.
  /// Listeners are told on the next frame, so this is safe to call while a
  /// screen is being disposed.
  void setVideoPosition(String key, Duration position) {
    final list = _videoPositions.where((e) => !e.startsWith('$key:')).toList();
    if (position > Duration.zero) {
      list.insert(0, '$key:${position.inMilliseconds}');
    }
    _prefs.setStringList('videoPositions', list.take(200).toList());
    WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
  }

  List<String> list(String key) => _prefs.getStringList(key) ?? const [];
  void setList(String key, List<String> value) =>
      _set(() => _prefs.setStringList(key, value));

  /// Every saved preference, for backups. Values are bool, int, double,
  /// String or a list of strings.
  Map<String, Object?> exportPrefs() => {
    for (final key in _prefs.getKeys()) key: _prefs.get(key),
  };

  /// Replaces all preferences by [values] (as given by [exportPrefs]).
  Future<void> replacePrefs(Map<String, Object?> values) async {
    await _prefs.clear();
    for (final entry in values.entries) {
      final v = entry.value;
      if (v is bool) {
        await _prefs.setBool(entry.key, v);
      } else if (v is int) {
        await _prefs.setInt(entry.key, v);
      } else if (v is double) {
        await _prefs.setDouble(entry.key, v);
      } else if (v is String) {
        await _prefs.setString(entry.key, v);
      } else if (v is List) {
        await _prefs.setStringList(entry.key, [for (final e in v) '$e']);
      }
    }
    notifyListeners();
  }

  /// Free-form storage for modules that serialise their own state.
  String? raw(String key) => _prefs.getString(key);
  void setRaw(String key, String value) =>
      _set(() => _prefs.setString(key, value));

  /// Recently opened documents as "path|page", most recent first.
  List<String> get _recentDocs =>
      _prefs.getStringList('recentDocs') ?? const [];

  List<String> get recentDocPaths => [
    for (final e in _recentDocs) e.substring(0, e.lastIndexOf('|')),
  ];

  int docPage(String path) {
    for (final e in _recentDocs) {
      if (e.startsWith('$path|')) {
        return int.parse(e.substring(path.length + 1));
      }
    }
    return 0;
  }

  /// With [notify] false, listeners are not told: required when called
  /// while a screen is being built or disposed.
  void setDocPage(String path, int page, {bool notify = true}) {
    final list = [
      '$path|$page',
      ..._recentDocs.where((e) => !e.startsWith('$path|')),
    ].take(30).toList();
    if (notify) {
      _set(() => _prefs.setStringList('recentDocs', list));
    } else {
      _prefs.setStringList('recentDocs', list);
    }
  }

  void forgetDoc(String path) => _set(
    () => _prefs.setStringList(
      'recentDocs',
      _recentDocs.where((e) => !e.startsWith('$path|')).toList(),
    ),
  );

  bool get readerNight => _prefs.getBool('readerNight') ?? false;
  set readerNight(bool v) => _set(() => _prefs.setBool('readerNight', v));

  double get readerTextSize => _prefs.getDouble('readerTextSize') ?? 15;
  set readerTextSize(double v) =>
      _set(() => _prefs.setDouble('readerTextSize', v));

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
