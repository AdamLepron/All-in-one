import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/util.dart';
import '../docs/docs_store.dart';
import '../docs/document_editor_page.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../gallery/media_library.dart';
import '../gallery/viewer_page.dart';
import '../music/music_controller.dart';
import '../music/song.dart';
import '../notes/notes_page.dart';
import '../notes/notes_store.dart';
import '../photo/photo_editor_page.dart';
import '../reader/documents.dart';
import '../tasks/organizer_store.dart';
import '../tasks/tasks_page.dart';
import '../transfer/transfer_page.dart';
import '../transfer/transfer_server.dart';
import '../video/video_player_page.dart';
import '../video_editor/video_editor_page.dart';
import 'incoming.dart';

const _icons = <ShareAction, IconData>{
  ShareAction.newNote: Icons.sticky_note_2_outlined,
  ShareAction.newTask: Icons.check_circle_outline,
  ShareAction.newDocument: Icons.edit_document,
  ShareAction.copyText: Icons.copy_rounded,
  ShareAction.open: Icons.open_in_new_rounded,
  ShareAction.editPhoto: Icons.tune_rounded,
  ShareAction.playVideo: Icons.play_circle_outline,
  ShareAction.editVideo: Icons.content_cut_rounded,
  ShareAction.playAudio: Icons.music_note_rounded,
  ShareAction.editDocument: Icons.edit_outlined,
  ShareAction.saveDownloads: Icons.download_rounded,
  ShareAction.saveGallery: Icons.photo_library_outlined,
  ShareAction.saveMovies: Icons.movie_outlined,
  ShareAction.saveMusic: Icons.library_music_outlined,
  ShareAction.saveDocuments: Icons.folder_open_rounded,
  ShareAction.sendWifi: Icons.wifi_tethering_rounded,
};

/// Folders for the "save" actions.
const downloadsDir = '$storageRoot/Download/All-in-One';
const picturesDir = '$storageRoot/Pictures/All-in-One';
const moviesFolder = '$storageRoot/Movies/All-in-One';
const musicDir = '$storageRoot/Music/All-in-One';

/// Entry point for content received from another app. "Open with" runs the
/// obvious action at once; anything else asks what to do.
Future<void> handleIncoming(BuildContext context, Incoming incoming) async {
  final direct = directAction(incoming);
  if (direct != null) {
    await runShareAction(context, direct, incoming);
    return;
  }
  await showIncomingSheet(context, incoming);
}

Future<void> showIncomingSheet(BuildContext context, Incoming incoming) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final actions = actionsFor(incoming);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Reçu d'une autre application", style: text.titleLarge),
                  const SizedBox(height: 6),
                  if (incoming.isText)
                    Text(
                      incoming.text!.trim(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Text(
                      incoming.files.length == 1
                          ? '${incoming.files.single.name} · ${formatBytes(incoming.files.single.size)}'
                          : '${incoming.files.length} fichiers · ${formatBytes(incoming.files.fold(0, (s, f) => s + f.size))}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            for (final action in actions)
              ListTile(
                leading: Icon(_icons[action]),
                title: Text(action.label),
                onTap: () {
                  Navigator.pop(sheet);
                  runShareAction(context, action, incoming);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// A [Media] for a received file, so the gallery viewer and the video
/// tools can open it. Its negative id never meets a library item.
Media _mediaOf(
  IncomingFile f, {
  required bool video,
  Duration duration = Duration.zero,
  Size? size,
}) => Media(
  id: -(f.path.hashCode.abs() + 1),
  video: video,
  path: f.path,
  name: f.name,
  date: DateTime.now(),
  uri: Uri.file(f.path).toString(),
  size: f.size,
  width: size?.width.round() ?? 0,
  height: size?.height.round() ?? 0,
  album: 'Reçus',
  duration: duration,
);

/// Reads the length and size of a received video with the player.
Future<Media?> probeVideo(IncomingFile f) async {
  final controller = VideoPlayerController.file(File(f.path));
  try {
    await controller.initialize().timeout(const Duration(seconds: 10));
    return _mediaOf(
      f,
      video: true,
      duration: controller.value.duration,
      size: controller.value.size,
    );
  } on Object {
    return null;
  } finally {
    try {
      await controller.dispose();
    } on Object {
      // Never opened.
    }
  }
}

Future<void> runShareAction(
  BuildContext context,
  ShareAction action,
  Incoming incoming,
) async {
  final navigator = Navigator.of(context);
  final file = incoming.files.isEmpty ? null : incoming.files.first;

  Future<void> save(String dir, String label) async {
    if (!await ensureFullFileAccess(context) || !context.mounted) return;
    try {
      final saved = await saveIncomingFiles(incoming.files, dir);
      if (context.mounted) {
        showMessage(
          context,
          '${saved.length} fichier${saved.length > 1 ? 's' : ''} enregistré${saved.length > 1 ? 's' : ''} dans $label',
        );
      }
    } on FileSystemException {
      if (context.mounted) showMessage(context, "L'enregistrement a échoué");
    }
  }

  switch (action) {
    case ShareAction.newNote:
      final note = Note(body: incoming.text!.trim());
      await context.read<NotesStore>().save(note);
      if (context.mounted) openNote(context, note);
    case ShareAction.newTask:
      final title = titleOfText(incoming.text!);
      showTaskEditor(context, null, Task(title: title));
    case ShareAction.newDocument:
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              DocumentEditorPage(initialText: incoming.text!.trim()),
        ),
      );
    case ShareAction.copyText:
      await Clipboard.setData(ClipboardData(text: incoming.text!));
      if (context.mounted) showMessage(context, 'Texte copié');
    case ShareAction.open:
      if (file == null) return;
      if (file.kind == IncomingKind.image) {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ViewerPage(
              items: [_mediaOf(file, video: false)],
              initialIndex: 0,
            ),
          ),
        );
      } else {
        await openDocument(context, file.path);
      }
    case ShareAction.editPhoto:
      if (file != null) {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoEditorPage(path: file.path),
          ),
        );
      }
    case ShareAction.playVideo:
      if (file != null) {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VideoPlayerPage(media: _mediaOf(file, video: true)),
          ),
        );
      }
    case ShareAction.editVideo:
      if (file == null) return;
      final media = await probeVideo(file);
      if (!context.mounted) return;
      if (media == null) {
        showMessage(context, 'Cette vidéo ne peut pas être lue');
      } else {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => VideoEditorPage(media: media),
          ),
        );
      }
    case ShareAction.playAudio:
      if (file == null) return;
      context.read<MusicController>().play(
        [
          Song(
            id: -(file.path.hashCode.abs() + 1),
            title: p.basenameWithoutExtension(file.name),
            artist: 'Reçu',
            album: 'Reçus',
            albumId: -1,
            duration: Duration.zero,
            uri: Uri.file(file.path).toString(),
            path: file.path,
          ),
        ],
        0,
        shuffled: false,
      );
    case ShareAction.editDocument:
      if (file == null ||
          !await ensureFullFileAccess(context) ||
          !context.mounted) {
        return;
      }
      final saved = (await saveIncomingFiles([file], docsDirectory)).single;
      if (context.mounted) {
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => DocumentEditorPage(path: saved),
          ),
        );
      }
    case ShareAction.saveDownloads:
      await save(downloadsDir, 'Téléchargements / All-in-One');
    case ShareAction.saveGallery:
      await save(picturesDir, 'Images / All-in-One');
    case ShareAction.saveMovies:
      await save(moviesFolder, 'Films / All-in-One');
    case ShareAction.saveMusic:
      await save(musicDir, 'Musique / All-in-One');
    case ShareAction.saveDocuments:
      await save(docsDirectory, 'Documents / All-in-One');
    case ShareAction.sendWifi:
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => TransferSessionPage(
            files: [for (final f in incoming.files) SharedFile(f.path, f.size)],
          ),
        ),
      );
  }
}
