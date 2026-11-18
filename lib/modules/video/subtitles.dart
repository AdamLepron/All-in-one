import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

/// A subtitle file found next to a video.
class SubtitleFile {
  const SubtitleFile(this.path, this.label);
  final String path;
  final String label;
}

const subtitleExtensions = ['.srt', '.vtt'];

/// Subtitle files stored beside [videoPath] whose name starts with the
/// video's: "film.srt", "film.fr.srt", "film.English.vtt".
List<SubtitleFile> findSubtitles(String videoPath) {
  final dir = Directory(p.dirname(videoPath));
  final base = p.basenameWithoutExtension(videoPath).toLowerCase();
  final found = <SubtitleFile>[];
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final ext = p.extension(name).toLowerCase();
      if (!subtitleExtensions.contains(ext)) continue;
      final stem = p.basenameWithoutExtension(name);
      final lower = stem.toLowerCase();
      if (lower == base) {
        found.add(SubtitleFile(entity.path, 'Sous-titres'));
      } else if (lower.startsWith('$base.')) {
        found.add(SubtitleFile(entity.path, stem.substring(base.length + 1)));
      }
    }
  } on FileSystemException {
    return const [];
  }
  found.sort((a, b) => a.path.compareTo(b.path));
  return found;
}

/// Reads a subtitle file, whatever its encoding: UTF-8 first, Latin-1 for
/// old files saved in Western encodings.
Future<String> readSubtitleText(String path) async {
  final bytes = await File(path).readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Parses [text] as SubRip or WebVTT according to [path]'s extension.
ClosedCaptionFile parseSubtitles(String path, String text) =>
    p.extension(path).toLowerCase() == '.vtt'
    ? WebVTTCaptionFile(text)
    : SubRipCaptionFile(text);
