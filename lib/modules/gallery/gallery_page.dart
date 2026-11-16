import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import 'media_grid.dart';
import 'media_library.dart';

enum _Tab {
  photos('Photos'),
  albums('Albums'),
  videos('Vidéos'),
  favorites('Favoris');

  const _Tab(this.label);
  final String label;
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  _Tab _tab = _Tab.photos;
  final _selection = MediaSelection();

  @override
  void initState() {
    super.initState();
    final library = context.read<MediaLibrary>();
    WidgetsBinding.instance.addPostFrameCallback((_) => library.load());
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    final settings = context.watch<AppSettings>();
    final items = switch (_tab) {
      _Tab.videos => library.videos,
      _Tab.favorites =>
        library.items.where((m) => settings.isFavoriteMedia(m.key)).toList(),
      _ => library.items,
    };

    return MediaScaffold(
      title: 'Galerie',
      selection: _selection,
      visibleItems: items,
      body: switch (library.status) {
        MediaStatus.unknown ||
        MediaStatus.loading => const Center(child: CircularProgressIndicator()),
        MediaStatus.denied => MediaMessage(
          icon: Icons.photo_library_outlined,
          title: 'Accès à vos photos',
          text: "Autorisez l'accès aux photos et vidéos pour afficher votre galerie. Rien ne quitte votre appareil.",
          action: FilledButton(
            onPressed: () async {
              await library.load();
              if (library.status == MediaStatus.denied) openAppSettings();
            },
            child: const Text("Autoriser l'accès"),
          ),
        ),
        MediaStatus.ready => Column(
          children: [
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _Tab.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final t = _Tab.values[i];
                  return ChoiceChip(
                    showCheckmark: false,
                    label: Text(t.label),
                    selected: t == _tab,
                    onSelected: (_) {
                      _selection.clear();
                      setState(() => _tab = t);
                    },
                  );
                },
              ),
            ),
            Expanded(
              child: _tab == _Tab.albums
                  ? _AlbumGrid(library.albums)
                  : items.isEmpty
                  ? MediaMessage(
                      icon: _tab == _Tab.favorites
                          ? Icons.favorite_border
                          : Icons.photo_outlined,
                      title: switch (_tab) {
                        _Tab.favorites => 'Aucun favori',
                        _Tab.videos => 'Aucune vidéo',
                        _ => 'Aucune photo',
                      },
                      text: _tab == _Tab.favorites
                          ? 'Touchez le cœur en affichant une photo pour la retrouver ici.'
                          : 'Les photos et vidéos du téléphone apparaîtront ici.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => library.load(request: false),
                      child: MediaGrid(items: items, selection: _selection),
                    ),
            ),
          ],
        ),
      },
    );
  }
}

/// Scaffold shared by the gallery and album screens: its app bar turns into
/// selection actions while items are selected.
class MediaScaffold extends StatelessWidget {
  const MediaScaffold({
    super.key,
    required this.title,
    required this.selection,
    required this.visibleItems,
    required this.body,
  });

  final String title;
  final MediaSelection selection;
  final List<Media> visibleItems;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return ListenableBuilder(
      listenable: selection,
      builder: (context, _) {
        final selected = [
          for (final m in visibleItems)
            if (selection.keys.contains(m.key)) m,
        ];
        return PopScope(
          canPop: !selection.active,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) selection.clear();
          },
          child: Scaffold(
            appBar: selection.active
                ? AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: selection.clear,
                    ),
                    title: Text('${selection.keys.length}'),
                    actions: [
                      IconButton(
                        tooltip: 'Partager',
                        icon: const Icon(Icons.share_outlined),
                        onPressed: () {
                          shareMedia(selected);
                          selection.clear();
                        },
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          selection.clear();
                          await trashMedia(context, selected);
                        },
                      ),
                    ],
                  )
                : AppBar(
                    title: Text(title),
                    actions: [
                      IconButton(
                        tooltip: 'Taille des vignettes',
                        icon: const Icon(Icons.grid_view_rounded),
                        onPressed: () => settings.galleryColumns =
                            const {3: 4, 4: 6, 6: 3}[settings.galleryColumns] ??
                            4,
                      ),
                    ],
                  ),
            body: body,
          ),
        );
      },
    );
  }
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid(this.albums);
  final List<MediaAlbum> albums;

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
        childAspectRatio: 0.8,
      ),
      itemCount: albums.length,
      itemBuilder: (_, i) {
        final album = albums[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AlbumPage(name: album.name),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: MediaThumb(album.items.first, showDuration: false),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${album.items.length} élément${album.items.length > 1 ? 's' : ''}',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.name});
  final String name;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = context
        .watch<MediaLibrary>()
        .items
        .where((m) => m.album == widget.name)
        .toList();
    return MediaScaffold(
      title: widget.name,
      selection: _selection,
      visibleItems: items,
      body: items.isEmpty
          ? const Center(child: Text('Cet album est vide'))
          : MediaGrid(items: items, selection: _selection),
    );
  }
}

class MediaMessage extends StatelessWidget {
  const MediaMessage({
    super.key,
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
