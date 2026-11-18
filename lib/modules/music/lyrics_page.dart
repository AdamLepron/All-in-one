import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import 'lyrics.dart';
import 'music_controller.dart';
import 'song.dart';

/// Lyrics of the song being played, following it line by line when the
/// file is synchronised (.lrc).
class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  static const _lineHeight = 56.0;

  final _scroll = ScrollController();
  int? _songId;
  Lyrics? _lyrics;
  bool _loading = false;
  int _active = -2;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String? _fileFor(Song song, AppSettings settings) =>
      settings.raw('lyrics:${song.id}') ?? findLyricsFile(song.path);

  Future<void> _load(Song song) async {
    _songId = song.id;
    _loading = true;
    _lyrics = null;
    _active = -2;
    final settings = context.read<AppSettings>();
    final path = _fileFor(song, settings);
    Lyrics? found;
    if (path != null) {
      try {
        found = await readLyrics(path);
      } on Object {
        found = null;
      }
    }
    if (!mounted || _songId != song.id) return;
    setState(() {
      _lyrics = found;
      _loading = false;
    });
  }

  Future<void> _choose(Song song) async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path == null || !mounted) return;
    context.read<AppSettings>().setRaw('lyrics:${song.id}', path);
    await _load(song);
  }

  void _follow(int active) {
    if (active == _active || !_scroll.hasClients) return;
    _active = active;
    if (active < 0) return;
    final target =
        active * _lineHeight - _scroll.position.viewportDimension / 2 + 120;
    _scroll.animateTo(
      target.clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final song = music.current;
    final scheme = Theme.of(context).colorScheme;
    if (song != null && song.id != _songId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(song);
      });
    }
    final lyrics = _lyrics;
    return Scaffold(
      appBar: AppBar(
        title: Text(song?.title ?? 'Paroles', maxLines: 1),
        actions: [
          if (song != null)
            IconButton(
              tooltip: 'Choisir un fichier de paroles',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => _choose(song),
            ),
        ],
      ),
      body: song == null
          ? const Center(child: Text('Aucun titre en lecture'))
          : _loading || (lyrics == null && song.id != _songId)
          ? const Center(child: CircularProgressIndicator())
          : lyrics == null || lyrics.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lyrics_outlined,
                      size: 64,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Aucune parole trouvée.\n\n'
                      'Placez un fichier .lrc portant le même nom que le morceau '
                      'dans le même dossier, ou choisissez-en un.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: () => _choose(song),
                      child: const Text('Choisir un fichier'),
                    ),
                  ],
                ),
              ),
            )
          : ValueListenableBuilder<Duration>(
              valueListenable: music.position,
              builder: (context, position, _) {
                final active = lyrics.activeAt(position);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _follow(active),
                );
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 120,
                  ),
                  itemCount: lyrics.lines.length,
                  itemExtent: lyrics.synced ? _lineHeight : null,
                  itemBuilder: (_, i) {
                    final line = lyrics.lines[i];
                    final current = i == active;
                    final child = Text(
                      line.text.isEmpty ? '♪' : line.text,
                      textAlign: TextAlign.center,
                      maxLines: lyrics.synced ? 2 : null,
                      overflow: lyrics.synced ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                        fontSize: current ? 22 : 18,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w500,
                        color: current
                            ? scheme.primary
                            : lyrics.synced
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    );
                    if (!lyrics.synced) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: child,
                      );
                    }
                    return InkWell(
                      onTap: line.time == null
                          ? null
                          : () => music.seek(line.time!),
                      child: Center(child: child),
                    );
                  },
                );
              },
            ),
    );
  }
}
