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

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}
