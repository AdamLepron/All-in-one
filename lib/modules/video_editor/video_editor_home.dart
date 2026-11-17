import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../gallery/gallery_page.dart' show MediaMessage;
import '../gallery/media_library.dart';
import '../gallery/media_grid.dart';
import 'video_editor_page.dart';

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
  @override
  void initState() {
    super.initState();
    final library = context.read<MediaLibrary>();
    WidgetsBinding.instance.addPostFrameCallback((_) => library.load());
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
                          onTap: () => editVideo(context, videos[i]),
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
