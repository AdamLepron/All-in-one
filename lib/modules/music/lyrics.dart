import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// One line of lyrics; [time] is null when the lyrics are not synchronised.
class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration? time;
  final String text;
}

class Lyrics {
  const Lyrics(this.lines);
  final List<LyricLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get synced => lines.isNotEmpty && lines.every((l) => l.time != null);

  /// Index of the line being sung at [position], or -1 before the first.
  int activeAt(Duration position) {
    if (!synced) return -1;
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (lines[mid].time! <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}

final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offset = RegExp(r'^\[offset:\s*(-?\d+)\s*\]', caseSensitive: false);
final _tag = RegExp(r'^\[[a-zA-Z]+:[^\]]*\]$');

/// Parses LRC text (one or several "[mm:ss.xx]" stamps before a line, and
/// the optional "[offset:ms]" tag). Text without stamps becomes plain lines.
Lyrics parseLyrics(String text) {
  final lines = <LyricLine>[];
  var offset = 0;
  var anyStamp = false;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final off = _offset.firstMatch(line);
    if (off != null) {
      offset = int.parse(off.group(1)!);
      continue;
    }
    final stamps = _stamp.allMatches(line).toList();
    if (stamps.isEmpty) {
      // Metadata such as [ar:Artist] is not lyrics.
      if (_tag.hasMatch(line)) continue;
      lines.add(LyricLine(null, line));
      continue;
    }
    anyStamp = true;
    final words = line.substring(stamps.last.end).trim();
    for (final m in stamps) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final fraction = m.group(3);
      final ms = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));
      final t = Duration(
        milliseconds: (minutes * 60 + seconds) * 1000 + ms - offset,
      );
      lines.add(LyricLine(t < Duration.zero ? Duration.zero : t, words));
    }
  }
  if (anyStamp) {
    // Keep only stamped lines, in time order.
    final stamped = lines.where((l) => l.time != null).toList()
      ..sort((a, b) => a.time!.compareTo(b.time!));
    return Lyrics(stamped);
  }
  // Plain text: drop blank lines at both ends only.
  while (lines.isNotEmpty && lines.first.text.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.text.isEmpty) {
    lines.removeLast();
  }
  return Lyrics(lines);
}

/// The .lrc (or .txt) file stored beside the song, if any.
String? findLyricsFile(String songPath) {
  if (songPath.isEmpty) return null;
  final base = p.withoutExtension(songPath);
  for (final ext in const ['.lrc', '.LRC', '.txt', '.TXT']) {
    if (File('$base$ext').existsSync()) return '$base$ext';
  }
  return null;
}

Future<Lyrics> readLyrics(String path) async {
  final bytes = await File(path).readAsBytes();
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes);
  }
  if (text.startsWith('﻿')) text = text.substring(1);
  return parseLyrics(text);
}
