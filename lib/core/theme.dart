import 'package:material_ui/material_ui.dart';

import 'l10n.dart';

/// Builds the app theme from a seed colour. [amoled] forces pure black
/// surfaces in dark mode.
ThemeData buildTheme(Color seed, Brightness brightness, {bool amoled = false}) {
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  if (amoled && brightness == Brightness.dark) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0C0C0C),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF191919),
      surfaceContainerHighest: const Color(0xFF212121),
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontFamily: 'Roboto',
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainer,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

/// The three module families, each with its own accent tint.
enum Family {
  media('Multimédia', Color(0xFFD6409F)),
  productivity('Productivité', Color(0xFF0A84FF)),
  tools('Utilitaires', Color(0xFF12A594));

  const Family(this._label, this.color);
  final String _label;
  String get label => tr(_label);
  final Color color;
}
