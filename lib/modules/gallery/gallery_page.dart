import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../files/files_ui.dart' show askName, showMessage;
import 'media_grid.dart';
import 'media_library.dart';
import 'media_search.dart';
import '../transfer/transfer_page.dart';
import 'vault_page.dart';

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
  bool _searching = false;
  String _query = '';

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
    final base = switch (_tab) {
      _Tab.videos => library.videos,
      _Tab.favorites =>
        library.items.where((m) => settings.isFavoriteMedia(m.key)).toList(),
      _ => library.items,
    };
    // A search looks through everything, whatever the tab.
    final items = _searching && _query.trim().isNotEmpty
        ? searchMedia(library.items, _query)
        : base;

    return MediaScaffold(
      title: 'Galerie',
      titleWidget: _searching
          ? TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Nom, album, date, « vidéo »…',
                filled: false,
                border: InputBorder.none,
              ),
            )
          : null,
      extraActions: [
        IconButton(
          tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            _query = '';
          }),
        ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Plus',
          onSelected: (action) => action(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const VaultPage()),
              ),
              child: const Text('Dossier protégé'),
            ),
          ],
        ),
      ],
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
              child: _searching && _query.trim().isNotEmpty
                  ? (items.isEmpty
                        ? const MediaMessage(
                            icon: Icons.search_off,
                            title: 'Aucun résultat',
                            text: 'Essayez un nom, un album, une année ou un mois.',
                          )
                        : MediaGrid(items: items, selection: _selection))
                  : _tab == _Tab.albums
                  ? _AlbumGrid(library.albums, settings.mediaAlbums, library)
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
    this.titleWidget,
    this.extraActions = const [],
    this.onRemove,
  });

  final String title;

  /// Replaces the title, for a search field.
  final Widget? titleWidget;

  /// Buttons added to the normal app bar.
  final List<Widget> extraActions;

  /// In an album: takes the selected items out of it (not off the phone).
  final void Function(List<Media> items)? onRemove;
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
                        tooltip: 'Ajouter à un album',
                        icon: const Icon(Icons.photo_album_outlined),
                        onPressed: () async {
                          await pickAlbumFor(context, selected);
                          selection.clear();
                        },
                      ),
                      PopupMenuButton<VoidCallback>(
                        tooltip: 'Plus',
                        onSelected: (action) => action(),
                        itemBuilder: (_) => [
                          if (onRemove != null)
                            PopupMenuItem(
                              value: () {
                                onRemove!(selected);
                                selection.clear();
                              },
                              child: const Text("Retirer de l'album"),
                            ),
                          PopupMenuItem(
                            value: () {
                              selection.clear();
                              sendByWifi(context, [
                                for (final m in selected) m.path,
                              ]);
                            },
                            child: const Text('Envoyer par Wi-Fi'),
                          ),
                          PopupMenuItem(
                            value: () async {
                              selection.clear();
                              await moveToVault(context, selected);
                            },
                            child: const Text(
                              'Déplacer vers le dossier protégé',
                            ),
                          ),
                        ],
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
                    title: titleWidget ?? Text(title),
                    actions: [
                      ...extraActions,
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
  const _AlbumGrid(this.albums, this.mine, this.library);
  final List<MediaAlbum> albums;
  final List<UserAlbum> mine;
  final MediaLibrary library;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final settings = context.read<AppSettings>();
    final byKey = {for (final m in library.items) m.key: m};
    // The user's own albums come first, after a tile to create one.
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: 1 + mine.length + albums.length,
      itemBuilder: (_, i) {
        if (i == 0) {
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              final name = await askName(
                context,
                title: 'Nouvel album',
                action: 'Créer',
              );
              if (name != null) settings.createMediaAlbum(name);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: scheme.surfaceContainerHighest,
                    ),
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 40,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nouvel album',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }
        if (i <= mine.length) {
          final a = mine[i - 1];
          final shown = [
            for (final k in a.keys)
              if (byKey[k] != null) byKey[k]!,
          ];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => UserAlbumPage(id: a.id)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: shown.isEmpty
                        ? ColoredBox(
                            color: scheme.secondaryContainer,
                            child: Icon(
                              Icons.photo_album_outlined,
                              size: 40,
                              color: scheme.onSecondaryContainer,
                            ),
                          )
                        : MediaThumb(shown.first, showDuration: false),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${shown.length} élément${shown.length > 1 ? 's' : ''}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }
        final album = albums[i - 1 - mine.length];
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

/// An album made by the user.
class UserAlbumPage extends StatefulWidget {
  const UserAlbumPage({super.key, required this.id});
  final int id;

  @override
  State<UserAlbumPage> createState() => _UserAlbumPageState();
}

class _UserAlbumPageState extends State<UserAlbumPage> {
  final _selection = MediaSelection();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final album = settings.mediaAlbums
        .where((a) => a.id == widget.id)
        .firstOrNull;
    if (album == null) return const Scaffold(body: SizedBox.shrink());
    final byKey = {
      for (final m in context.watch<MediaLibrary>().items) m.key: m,
    };
    final items = [
      for (final k in album.keys)
        if (byKey[k] != null) byKey[k]!,
    ];
    return MediaScaffold(
      title: album.name,
      selection: _selection,
      visibleItems: items,
      onRemove: (list) => settings.removeFromMediaAlbum(album.id, [
        for (final m in list) m.key,
      ]),
      extraActions: [
        PopupMenuButton<String>(
          tooltip: 'Plus',
          onSelected: (v) async {
            if (v == 'rename') {
              final name = await askName(
                context,
                title: "Renommer l'album",
                initial: album.name,
                action: 'Renommer',
              );
              if (name != null) settings.renameMediaAlbum(album.id, name);
            } else {
              settings.deleteMediaAlbum(album.id);
              if (context.mounted) Navigator.pop(context);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Renommer')),
            PopupMenuItem(
              value: 'delete',
              child: Text("Supprimer l'album (les photos restent)"),
            ),
          ],
        ),
      ],
      body: items.isEmpty
          ? const MediaMessage(
              icon: Icons.photo_album_outlined,
              title: 'Album vide',
              text: "Sélectionnez des photos dans la galerie, puis « Ajouter à un album ».",
            )
          : MediaGrid(items: items, selection: _selection),
    );
  }
}

/// Asks which album to put [items] in (or to create one); shows the result.
Future<void> pickAlbumFor(BuildContext context, List<Media> items) async {
  final settings = context.read<AppSettings>();
  final keys = [for (final m in items) m.key];
  final choice = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Ajouter à un album')),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Nouvel album'),
              onTap: () => Navigator.pop(sheet, -1),
            ),
            for (final a in settings.mediaAlbums)
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(a.name),
                subtitle: Text(
                  '${a.keys.length} élément${a.keys.length > 1 ? 's' : ''}',
                ),
                onTap: () => Navigator.pop(sheet, a.id),
              ),
          ],
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == -1) {
    final name = await askName(context, title: 'Nouvel album', action: 'Créer');
    if (name == null) return;
    final a = settings.createMediaAlbum(name, keys: keys);
    if (context.mounted) showMessage(context, 'Ajouté à « ${a.name} »');
  } else {
    settings.addToMediaAlbum(choice, keys);
    final name = settings.mediaAlbums.firstWhere((a) => a.id == choice).name;
    if (context.mounted) showMessage(context, 'Ajouté à « $name »');
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
