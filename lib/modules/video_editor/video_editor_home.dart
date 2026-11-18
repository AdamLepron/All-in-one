import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../gallery/gallery_page.dart' show MediaMessage;
import '../gallery/media_library.dart';
import '../gallery/media_grid.dart';
import '../../core/util.dart';
import 'project_store.dart';
import 'video_editor_page.dart';
import 'video_project.dart';

void editVideo(BuildContext context, Media media) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => VideoEditorPage(media: media)),
  );
}

/// Module entry: pick the video to start a montage from.
class VideoEditorHome extends StatefulWidget {
  const VideoEditorHome({super.key});

  @override
  State<VideoEditorHome> createState() => _VideoEditorHomeState();
}

class _VideoEditorHomeState extends State<VideoEditorHome> {
  final _store = ProjectStore();
  List<SavedProject> _projects = const [];

  @override
  void initState() {
    super.initState();
    final library = context.read<MediaLibrary>();
    WidgetsBinding.instance.addPostFrameCallback((_) => library.load());
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    final list = await _store.list();
    if (mounted) setState(() => _projects = list);
  }

  Future<void> _open({VideoProject? project, Media? media}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VideoEditorPage(project: project, media: media, store: _store),
      ),
    );
    // The montage may have been saved while editing.
    if (mounted) _loadProjects();
  }

  Future<void> _delete(SavedProject saved) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Supprimer « ${saved.project.name} » ?'),
        content: const Text(
          'Le montage est supprimé, pas les vidéos originales.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(saved.project.id);
      await _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    final videos = library.videos;
    return Scaffold(
      appBar: AppBar(title: const Text('Éditeur vidéo')),
      body: switch (library.status) {
        MediaStatus.unknown ||
        MediaStatus.loading => const Center(child: CircularProgressIndicator()),
        MediaStatus.denied => MediaMessage(
          icon: Icons.video_library_outlined,
          title: 'Accès à vos vidéos',
          text: "Autorisez l'accès aux vidéos pour choisir celle à monter.",
          action: FilledButton(
            onPressed: () async {
              await library.load();
              if (library.status == MediaStatus.denied) openAppSettings();
            },
            child: const Text("Autoriser l'accès"),
          ),
        ),
        MediaStatus.ready =>
          videos.isEmpty
              ? const MediaMessage(
                  icon: Icons.videocam_off_outlined,
                  title: 'Aucune vidéo',
                  text: 'Les vidéos du téléphone apparaîtront ici.',
                )
              : Column(
                  children: [
                    if (_projects.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Montages en cours',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 132,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          children: [
                            for (final saved in _projects)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: SizedBox(
                                  width: 120,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => _open(project: saved.project),
                                    onLongPress: () => _delete(saved),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          height: 80,
                                          width: 120,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: MediaThumb(
                                              saved.project.clips.first.media,
                                              showDuration: false,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          saved.project.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          '${clock(saved.project.totalMs)} · ${relativeDate(saved.saved)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 24),
                    ],
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Choisissez la première vidéo. Vous pourrez couper, accélérer, pivoter, "
                          "ajouter d'autres vidéos et une musique. Les originales ne sont jamais modifiées.",
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: videos.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _open(media: videos[i]),
                          child: MediaThumb(videos[i]),
                        ),
                      ),
                    ),
                  ],
                ),
      },
    );
  }
}
