import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../files/files_ui.dart' show showMessage;
import 'artwork.dart';
import 'mini_player.dart';
import 'music_controller.dart';
import 'song.dart';

const _green = Color(0xFF1DB954);

enum _Filter {
  home('Accueil'),
  songs('Titres'),
  albums('Albums'),
  artists('Artistes'),
  playlists('Playlists'),
  favorites('Favoris'),
  recent('Récents');

  const _Filter(this.label);
  final String label;
}

const _sortLabels = ['Titre', 'Ajout récent', 'Artiste'];

class MusicPage extends StatefulWidget {
  const MusicPage({super.key});

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage> {
  _Filter _filter = _Filter.home;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final music = context.read<MusicController>();
    if (music.status != LibraryStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) => music.loadLibrary());
    }
  }

  @override
  Widget build(BuildContext context) {
    final music = context.watch<MusicController>();
    final settings = context.watch<AppSettings>();

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() {
            _searching = false;
            _query = '';
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _searching
              ? TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    hintText: 'Titres, artistes, albums',
                    filled: false,
                    border: InputBorder.none,
                  ),
                )
              : const Text('Musique'),
          actions: [
            if (music.status == LibraryStatus.ready)
              IconButton(
                tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
              ),
            if (music.status == LibraryStatus.ready && !_searching)
              IconButton(
                tooltip: 'Actualiser la bibliothèque',
                icon: const Icon(Icons.refresh),
                onPressed: music.loadLibrary,
              ),
          ],
        ),
        bottomNavigationBar: const SafeArea(child: MiniPlayer()),
        body: switch (music.status) {
          LibraryStatus.unknown || LibraryStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          LibraryStatus.denied => _Message(
            icon: Icons.library_music_outlined,
            title: 'Accès à votre musique',
            text: "Autorisez l'accès aux fichiers audio pour afficher votre bibliothèque.",
            action: FilledButton(
              onPressed: () async {
                await music.loadLibrary();
                if (music.status == LibraryStatus.denied) openAppSettings();
              },
              child: const Text("Autoriser l'accès"),
            ),
          ),
          LibraryStatus.ready =>
            music.songs.isEmpty
                ? const _Message(
                    icon: Icons.music_off_outlined,
                    title: 'Aucun morceau trouvé',
                    text: 'Copiez des fichiers audio dans le dossier Musique du téléphone, puis actualisez.',
                  )
                : _searching
                ? _searchResults(music)
                : _library(music, settings),
        },
      ),
    );
  }

  Widget _searchResults(MusicController music) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const SizedBox.shrink();
    final hits = music.songs.where((s) => s.matches(q)).toList();
    if (hits.isEmpty) return const Center(child: Text('Aucun résultat'));
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (_, i) =>
          SongTile(hits[i], onTap: () => music.play(hits, i)),
    );
  }

  Widget _library(MusicController music, AppSettings settings) {
    final byId = {for (final s in music.songs) s.id: s};
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _Filter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final f = _Filter.values[i];
              return ChoiceChip(
                showCheckmark: false,
                label: Text(f.label),
                selected: f == _filter,
                onSelected: (_) => setState(() => _filter = f),
              );
            },
          ),
        ),
        Expanded(
          child: switch (_filter) {
            _Filter.home => _Home(
              music: music,
              settings: settings,
              onSeeAll: (f) => setState(() => _filter = f),
            ),
            _Filter.songs => SongList(
              songs: music.sortedSongs(settings.musicSort),
              sortLabel: _sortLabels[settings.musicSort],
              onSort: () => _showSort(settings),
            ),
            _Filter.albums => _AlbumGrid(music.albums),
            _Filter.playlists => const _PlaylistList(),
            _Filter.artists => _ArtistList(music.artists),
            _Filter.favorites => SongList(
              songs: [
                for (final s in music.sortedSongs(0))
                  if (settings.isFavorite(s.id)) s,
              ],
              emptyText: 'Touchez le cœur sur l\'écran de lecture pour ajouter un favori.',
            ),
            _Filter.recent => SongList(
              songs: [
                for (final id in settings.recentSongs)
                  if (byId[id] != null) byId[id]!,
              ],
              emptyText: 'Les morceaux écoutés apparaîtront ici.',
            ),
          },
        ),
      ],
    );
  }

  void _showSort(AppSettings settings) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, label) in _sortLabels.indexed)
              ListTile(
                title: Text(label),
                selected: settings.musicSort == i,
                trailing: settings.musicSort == i
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  settings.musicSort = i;
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Song list with a header: count, optional sort, shuffle and play buttons.
class SongList extends StatelessWidget {
  const SongList({
    super.key,
    required this.songs,
    this.sortLabel,
    this.onSort,
    this.emptyText = '',
    this.header,
    this.showTrackNumbers = false,
    this.onRemove,
  });

  /// When set, each song's menu offers to remove it (from a playlist).
  final void Function(Song song)? onRemove;
  final List<Song> songs;
  final String? sortLabel;
  final VoidCallback? onSort;
  final String emptyText;
  final Widget? header;
  final bool showTrackNumbers;

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicController>();
    final scheme = Theme.of(context).colorScheme;
    if (songs.isEmpty && header == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: songs.length + 1,
      itemBuilder: (_, row) {
        if (row == 0) {
          return Column(
            children: [
              ?header,
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
                child: Row(
                  children: [
                    if (onSort != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onSort,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            children: [
                              const Icon(Icons.swap_vert_rounded, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                sortLabel ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Text(
                        '${songs.length} titre${songs.length > 1 ? 's' : ''}',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Lecture aléatoire',
                      icon: const Icon(Icons.shuffle_rounded),
                      onPressed: () => music.shuffleAll(songs),
                    ),
                    const SizedBox(width: 4),
                    Material(
                      color: _green,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => music.play(songs, 0, shuffled: false),
                        // Spoken by screen readers; there is no visible text.
                        child: Semantics(
                          label: 'Tout lire',
                          button: true,
                          excludeSemantics: true,
                          child: const SizedBox(
                            width: 52,
                            height: 52,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 34,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        final i = row - 1;
        return SongTile(
          songs[i],
          trackNumber: showTrackNumbers ? i + 1 : null,
          onRemove: onRemove,
          onTap: () => music.play(songs, i),
        );
      },
    );
  }
}

class SongTile extends StatelessWidget {
  const SongTile(
    this.song, {
    super.key,
    required this.onTap,
    this.trackNumber,
    this.onRemove,
  });
  final Song song;
  final void Function(Song song)? onRemove;
  final VoidCallback onTap;
  final int? trackNumber;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = context.select<MusicController, bool>(
      (m) => m.current?.id == song.id,
    );
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: trackNumber == null
          ? Artwork(song, size: 48)
          : SizedBox(
              width: 28,
              child: Center(
                child: Text(
                  '$trackNumber',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrent ? _green : null,
        ),
      ),
      subtitle: Text(
        '${song.artist} · ${formatDuration(song.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Options',
        icon: const Icon(Icons.more_vert),
        onPressed: () => _showActions(context),
      ),
      onTap: onTap,
      onLongPress: () => _showActions(context),
    );
  }

  void _showActions(BuildContext context) {
    final music = context.read<MusicController>();
    final settings = context.read<AppSettings>();
    final favorite = settings.isFavorite(song.id);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        // Scrolls on short screens, where the longer menu no longer fits.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Artwork(song, size: 48),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${song.artist} · ${song.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: const Text('Lire ensuite'),
                onTap: () {
                  Navigator.pop(sheet);
                  music.playNext(song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: const Text("Ajouter à la file d'attente"),
                onTap: () {
                  Navigator.pop(sheet);
                  music.addToQueue(song);
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Ajouter à une playlist'),
                onTap: () {
                  Navigator.pop(sheet);
                  showAddToPlaylist(context, song);
                },
              ),
              if (onRemove != null)
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline_rounded),
                  title: const Text('Retirer de la playlist'),
                  onTap: () {
                    Navigator.pop(sheet);
                    onRemove!(song);
                  },
                ),
              ListTile(
                leading: Icon(
                  favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                ),
                title: Text(
                  favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  settings.toggleFavorite(song.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid(this.albums);
  final List<SongGroup> albums;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: albums.length,
      itemBuilder: (_, i) {
        final album = albums[i];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CollectionPage(group: album, isAlbum: true),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Artwork(album.songs.first, radius: 10),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                album.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtistList extends StatelessWidget {
  const _ArtistList(this.artists);
  final List<SongGroup> artists;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: artists.length,
      itemBuilder: (_, i) {
        final artist = artists[i];
        return ListTile(
          leading: Artwork(artist.songs.first, size: 52, radius: 26),
          title: Text(
            artist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(artist.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CollectionPage(group: artist, isAlbum: false),
            ),
          ),
        );
      },
    );
  }
}

/// Detail screen of an album or an artist.
class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key, required this.group, required this.isAlbum});
  final SongGroup group;
  final bool isAlbum;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final minutes = group.duration.inMinutes;
    return Scaffold(
      appBar: AppBar(title: const SizedBox.shrink()),
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: SongList(
        songs: group.songs,
        showTrackNumbers: isAlbum,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Column(
            children: [
              Artwork(
                group.songs.first,
                size: 200,
                radius: isAlbum ? 12 : 100,
                large: true,
              ),
              const SizedBox(height: 16),
              Text(
                group.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isAlbum
                    ? '${group.subtitle} · $minutes min'
                    : '${group.subtitle} · $minutes min',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              style: style.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Asks for a text; null when cancelled.
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Nom'),
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Bottom sheet to put [song] in an existing or a new playlist.
void showAddToPlaylist(BuildContext context, Song song) {
  final settings = context.read<AppSettings>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('Nouvelle playlist'),
            onTap: () async {
              Navigator.pop(sheet);
              final name = await askName(context, title: 'Nouvelle playlist');
              if (name == null) return;
              final p = settings.createPlaylist(name, songId: song.id);
              if (context.mounted) {
                showMessage(context, 'Ajouté à « ${p.name} »');
              }
            },
          ),
          for (final p in settings.playlists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${p.songIds.length} titre${p.songIds.length > 1 ? 's' : ''}',
              ),
              onTap: () {
                Navigator.pop(sheet);
                settings.addToPlaylist(p.id, song.id);
                showMessage(context, 'Ajouté à « ${p.name} »');
              },
            ),
        ],
      ),
    ),
  );
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final lists = settings.playlists;
    return ListView(
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.add_rounded)),
          title: const Text('Nouvelle playlist'),
          onTap: () async {
            final name = await askName(context, title: 'Nouvelle playlist');
            if (name != null) settings.createPlaylist(name);
          },
        ),
        for (final p in lists)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.queue_music_rounded)),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${p.songIds.length} titre${p.songIds.length > 1 ? 's' : ''}',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => PlaylistPage(id: p.id)),
            ),
          ),
        if (lists.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Créez une playlist, puis ajoutez-y des titres depuis leur menu ⋮.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Songs of one playlist, with rename and delete.
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final music = context.watch<MusicController>();
    final playlist = settings.playlists.where((p) => p.id == id).firstOrNull;
    if (playlist == null) return const Scaffold(body: SizedBox.shrink());
    final byId = {for (final s in music.songs) s.id: s};
    final songs = [
      for (final sid in playlist.songIds)
        if (byId[sid] != null) byId[sid]!,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (v) async {
              if (v == 'rename') {
                final name = await askName(
                  context,
                  title: 'Renommer',
                  initial: playlist.name,
                );
                if (name != null) settings.renamePlaylist(id, name);
              } else {
                settings.deletePlaylist(id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Supprimer la playlist'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: SongList(
        songs: songs,
        emptyText: 'Playlist vide. Ajoutez des titres depuis leur menu ⋮.',
        onRemove: (s) => settings.removeFromPlaylist(id, s.id),
      ),
    );
  }
}

/// Landing tab: what to resume, the user's playlists and the latest additions.
class _Home extends StatelessWidget {
  const _Home({
    required this.music,
    required this.settings,
    required this.onSeeAll,
  });
  final MusicController music;
  final AppSettings settings;
  final ValueChanged<_Filter> onSeeAll;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final s in music.songs) s.id: s};
    final recent = [
      for (final id in settings.recentSongs)
        if (byId[id] != null) byId[id]!,
    ];
    // Mode 1 is "recently added", already cached for the whole library.
    final added = music.sortedSongs(1);
    final favorites = [
      for (final s in music.sortedSongs(0))
        if (settings.isFavorite(s.id)) s,
    ];
    final playlists = settings.playlists;
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => music.shuffleAll(music.sortedSongs(0)),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Tout en aléatoire'),
                ),
              ),
            ],
          ),
        ),
        if (recent.isNotEmpty)
          _Shelf(
            title: 'Reprendre',
            songs: recent.take(12).toList(),
            onMore: () => onSeeAll(_Filter.recent),
          ),
        if (playlists.isNotEmpty) ...[
          _ShelfTitle(
            'Vos playlists',
            onMore: () => onSeeAll(_Filter.playlists),
          ),
          SizedBox(
            height: 112,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in playlists)
                  _PlaylistCard(
                    name: p.name,
                    count: p.songIds.length,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaylistPage(id: p.id),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (favorites.isNotEmpty)
          _Shelf(
            title: 'Vos favoris',
            songs: favorites.take(12).toList(),
            onMore: () => onSeeAll(_Filter.favorites),
          ),
        _Shelf(
          title: 'Ajoutés récemment',
          songs: added.take(12).toList(),
          onMore: () => onSeeAll(_Filter.songs),
        ),
      ],
    );
  }
}

class _ShelfTitle extends StatelessWidget {
  const _ShelfTitle(this.title, {required this.onMore});
  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        TextButton(onPressed: onMore, child: const Text('Tout voir')),
      ],
    ),
  );
}

class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.songs,
    required this.onMore,
  });
  final String title;
  final List<Song> songs;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final music = context.read<MusicController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShelfTitle(title, onMore: onMore),
        SizedBox(
          // Cover, then two lines of text that grow with the system font.
          height: 130 + 36 * MediaQuery.textScalerOf(context).scale(1),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: songs.length,
            itemBuilder: (_, i) => SizedBox(
              width: 120,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => music.play(songs, i, shuffled: false),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(songs[i], size: 112, radius: 10),
                      const SizedBox(height: 6),
                      Text(
                        songs[i].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        songs[i].artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.name,
    required this.count,
    required this.onTap,
  });
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 140,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.queue_music_rounded,
                    color: scheme.onSecondaryContainer,
                  ),
                  const Spacer(),
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  Text(
                    '$count titre${count > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
