import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../gallery/gallery_page.dart' show MediaMessage;
import '../gallery/media_grid.dart';
import '../gallery/media_library.dart';
import 'photo_editor_page.dart';

void editPhoto(BuildContext context, Media media) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PhotoEditorPage(path: media.path)),
  );
}

/// Module entry: pick a photo from the library to edit.
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key});

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  @override
  void initState() {
    super.initState();
    final library = context.read<MediaLibrary>();
    WidgetsBinding.instance.addPostFrameCallback((_) => library.load());
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<MediaLibrary>();
    final photos = library.items.where((m) => !m.video).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Éditeur photo')),
      body: switch (library.status) {
        MediaStatus.unknown ||
        MediaStatus.loading => const Center(child: CircularProgressIndicator()),
        MediaStatus.denied => MediaMessage(
          icon: Icons.photo_library_outlined,
          title: 'Accès à vos photos',
          text: "Autorisez l'accès aux photos pour choisir celle à retoucher.",
          action: FilledButton(
            onPressed: () async {
              await library.load();
              if (library.status == MediaStatus.denied) openAppSettings();
            },
            child: const Text("Autoriser l'accès"),
          ),
        ),
        MediaStatus.ready =>
          photos.isEmpty
              ? const MediaMessage(
                  icon: Icons.photo_outlined,
                  title: 'Aucune photo',
                  text: 'Les photos du téléphone apparaîtront ici.',
                )
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Choisissez une photo. L\'original n\'est jamais modifié : '
                          'le résultat est enregistré en copie.',
                        ),
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 2,
                              crossAxisSpacing: 2,
                            ),
                        itemCount: photos.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => editPhoto(context, photos[i]),
                          child: MediaThumb(photos[i]),
                        ),
                      ),
                    ),
                  ],
                ),
      },
    );
  }
}
