import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../gallery/gallery_page.dart' show MediaMessage;
import '../gallery/media_grid.dart';
import '../gallery/media_library.dart';
import '../video_editor/video_editor_home.dart';
import 'video_player_page.dart';

/// Plays [media]; with a [list], the following videos play automatically.
void playVideo(
  BuildContext context,
  Media media, [
  List<Media> list = const [],
]) {
  final index = list.indexOf(media);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VideoPlayerPage(
        media: media,
        playlist: index < 0 ? const [] : list,
        index: index < 0 ? 0 : index,
      ),
    ),
  );
}

/// Video library: every video of the device, by folder, with resume.
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  String? _folder;
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final library = context.read<MediaLibrary>();
    WidgetsBinding.instance.addPostFrameCallback((_) => library.load());
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    final settings = context.watch<AppSettings>();
    final all = library.videos;
    final folders = {for (final v in all) v.album}.toList()..sort();
    final q = _query.trim().toLowerCase();
    final videos = all
        .where((v) => _folder == null || v.album == _folder)
        .where((v) => q.isEmpty || v.name.toLowerCase().contains(q))
        .toList();
    final lastKey = settings.lastVideoKey;
    final last = lastKey == null ? null : library.byKey(lastKey);

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
                    hintText: 'Rechercher une vidéo',
                    filled: false,
                    border: InputBorder.none,
                  ),
                )
              : const Text('Vidéos'),
          actions: [
            if (library.status == MediaStatus.ready && all.isNotEmpty)
              IconButton(
                tooltip: _searching ? 'Fermer la recherche' : 'Rechercher',
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _query = '';
                }),
              ),
          ],
        ),
        body: switch (library.status) {
          MediaStatus.unknown || MediaStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          MediaStatus.denied => MediaMessage(
            icon: Icons.video_library_outlined,
            title: 'Accès à vos vidéos',
            text: "Autorisez l'accès aux vidéos pour afficher votre bibliothèque.",
            action: FilledButton(
              onPressed: () async {
                await library.load();
                if (library.status == MediaStatus.denied) openAppSettings();
              },
              child: const Text("Autoriser l'accès"),
            ),
          ),
          MediaStatus.ready =>
            all.isEmpty
                ? const MediaMessage(
                    icon: Icons.videocam_off_outlined,
                    title: 'Aucune vidéo trouvée',
                    text: 'Les vidéos du téléphone apparaîtront ici.',
                  )
                : RefreshIndicator(
                    onRefresh: () => library.load(request: false),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        if (last != null && !_searching)
                          _ResumeCard(media: last),
                        if (!_searching)
                          SizedBox(
                            height: 48,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              children: [
                                for (final f in [null, ...folders])
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ChoiceChip(
                                      showCheckmark: false,
                                      label: Text(f ?? 'Toutes'),
                                      selected: f == _folder,
                                      onSelected: (_) =>
                                          setState(() => _folder = f),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (videos.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: Text('Aucun résultat')),
                          ),
                        for (final v in videos)
                          _VideoTile(media: v, list: videos),
                      ],
                    ),
                  ),
        },
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.media, this.list = const []});
  final Media media;
  final List<Media> list;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final position = settings.videoPosition(media.key);
    final total = media.duration.inMilliseconds;
    return InkWell(
      onTap: () => playVideo(context, media, list),
      onLongPress: () => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.content_cut_rounded),
                title: const Text('Monter cette vidéo'),
                onTap: () {
                  Navigator.pop(sheet);
                  editVideo(context, media);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('Partager'),
                onTap: () {
                  Navigator.pop(sheet);
                  shareMedia([media]);
                },
              ),
            ],
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 132,
                height: 76,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaThumb(media),
                    if (position > Duration.zero && total > 0)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: position.inMilliseconds / total,
                          backgroundColor: Colors.black38,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatBytes(media.size)} · ${relativeDate(media.date)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.media});
  final Media media;

  @override
  Widget build(BuildContext context) {
    final settings = context.read<AppSettings>();
    final scheme = Theme.of(context).colorScheme;
    final position = settings.videoPosition(media.key);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => playVideo(context, media),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 96,
                    height: 56,
                    child: MediaThumb(media, showDuration: false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reprendre à ${formatDuration(position)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        media.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.play_circle_fill_rounded,
                  size: 40,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
