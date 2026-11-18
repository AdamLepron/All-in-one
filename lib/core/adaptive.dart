import 'dart:math' as math;

/// Widest the app grows: beyond it (tablets, foldables, landscape) content
/// stays centred instead of stretching across the whole screen.
const maxContentWidth = 1100.0;

/// Screen width from which the bottom bar becomes a side rail.
const railBreakpoint = 720.0;

/// Width the app actually uses on a screen [screen] wide.
double contentWidth(double screen) => math.min(screen, maxContentWidth);

/// Whether the navigation goes on the side for a window [screen] wide.
bool useRail(double screen) => contentWidth(screen) >= railBreakpoint;

/// Number of columns of tiles at least [minTile] wide in [width], never
/// fewer than [min] nor more than [max].
int columnsFor(double width, double minTile, {int min = 2, int max = 8}) =>
    (width / minTile).floor().clamp(min, max);
