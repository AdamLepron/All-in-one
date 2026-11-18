import 'dart:io';

import 'package:path/path.dart' as p;

import '../files/file_ops.dart';

enum IncomingKind { image, video, audio, pdf, text, document, other }

/// One file received from another app, already copied to a local path.
class IncomingFile {
  const IncomingFile(this.path, this.name, this.mime);
  final String path;
  final String name;
  final String? mime;

  IncomingKind get kind {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (ext == 'pdf' || mime == 'application/pdf') return IncomingKind.pdf;
    if (const {'txt', 'md', 'markdown'}.contains(ext) ||
        mime == 'text/plain' ||
        mime == 'text/markdown' ||
        mime == 'text/x-markdown') {
      return IncomingKind.text;
    }
    // The extension is more reliable than the type given by the sender.
    switch (kindOfPath(name)) {
      case FileKind.image:
        return IncomingKind.image;
      case FileKind.video:
        return IncomingKind.video;
      case FileKind.audio:
        return IncomingKind.audio;
      case FileKind.document:
        return IncomingKind.document;
      default:
        break;
    }
    final type = mime ?? '';
    if (type.startsWith('image/')) return IncomingKind.image;
    if (type.startsWith('video/')) return IncomingKind.video;
    if (type.startsWith('audio/')) return IncomingKind.audio;
    return IncomingKind.other;
  }

  int get size => File(path).existsSync() ? File(path).lengthSync() : 0;
}

/// What another app handed over: files, or some text such as a link.
class Incoming {
  const Incoming({this.files = const [], this.text, this.view = false});

  final List<IncomingFile> files;
  final String? text;

  /// True for "Open with", false for "Share".
  final bool view;

  bool get isText => files.isEmpty && (text ?? '').trim().isNotEmpty;

  static Incoming? fromMap(Map<Object?, Object?> map) {
    final files = <IncomingFile>[
      for (final f in (map['files'] as List? ?? const []))
        if (f is Map && f['path'] != null)
          IncomingFile(
            f['path']! as String,
            (f['name'] as String?) ?? p.basename(f['path']! as String),
            f['mime'] as String?,
          ),
    ];
    final text = map['text'] as String?;
    if (files.isEmpty && (text ?? '').trim().isEmpty) return null;
    return Incoming(files: files, text: text, view: map['action'] == 'view');
  }
}

/// Everything that can be done with received content.
enum ShareAction {
  newNote('Nouvelle note'),
  newTask('Nouvelle tâche'),
  newDocument('Nouveau document'),
  copyText('Copier le texte'),
  open('Ouvrir'),
  editPhoto('Modifier la photo'),
  playVideo('Lire la vidéo'),
  editVideo('Monter la vidéo'),
  playAudio('Écouter'),
  editDocument('Modifier dans Documents'),
  saveDownloads('Enregistrer dans Téléchargements'),
  saveGallery('Enregistrer dans Images'),
  saveMovies('Enregistrer dans Films'),
  saveMusic('Enregistrer dans Musique'),
  saveDocuments('Enregistrer dans Documents'),
  sendWifi('Envoyer à un autre appareil par Wi-Fi');

  const ShareAction(this.label);
  final String label;
}

/// Actions offered for [incoming], the most natural first.
List<ShareAction> actionsFor(Incoming incoming) {
  if (incoming.isText) {
    return const [
      ShareAction.newNote,
      ShareAction.newTask,
      ShareAction.newDocument,
      ShareAction.copyText,
    ];
  }
  final files = incoming.files;
  if (files.length == 1) {
    return switch (files.single.kind) {
      IncomingKind.image => const [
        ShareAction.open,
        ShareAction.editPhoto,
        ShareAction.saveGallery,
        ShareAction.sendWifi,
      ],
      IncomingKind.video => const [
        ShareAction.playVideo,
        ShareAction.editVideo,
        ShareAction.saveMovies,
        ShareAction.sendWifi,
      ],
      IncomingKind.audio => const [
        ShareAction.playAudio,
        ShareAction.saveMusic,
        ShareAction.sendWifi,
      ],
      IncomingKind.pdf => const [
        ShareAction.open,
        ShareAction.saveDocuments,
        ShareAction.sendWifi,
      ],
      IncomingKind.text => const [
        ShareAction.open,
        ShareAction.editDocument,
        ShareAction.saveDocuments,
        ShareAction.sendWifi,
      ],
      IncomingKind.document => const [
        ShareAction.open,
        ShareAction.saveDocuments,
        ShareAction.sendWifi,
      ],
      IncomingKind.other => const [
        ShareAction.saveDownloads,
        ShareAction.sendWifi,
      ],
    };
  }
  final allImages = files.every((f) => f.kind == IncomingKind.image);
  return [
    ShareAction.saveDownloads,
    if (allImages) ShareAction.saveGallery,
    ShareAction.sendWifi,
  ];
}

/// The action run at once for "Open with", when there is an obvious one.
ShareAction? directAction(Incoming incoming) {
  if (!incoming.view || incoming.files.length != 1) return null;
  return switch (incoming.files.single.kind) {
    IncomingKind.image ||
    IncomingKind.pdf ||
    IncomingKind.text ||
    IncomingKind.document => ShareAction.open,
    IncomingKind.video => ShareAction.playVideo,
    IncomingKind.audio => ShareAction.playAudio,
    IncomingKind.other => null,
  };
}

/// Copies [files] into [dir], never overwriting; returns the new paths.
Future<List<String>> saveIncomingFiles(
  List<IncomingFile> files,
  String dir,
) async {
  await Directory(dir).create(recursive: true);
  final saved = <String>[];
  for (final f in files) {
    final target = await uniquePath(dir, f.name);
    await File(f.path).copy(target);
    saved.add(target);
  }
  return saved;
}

/// First line of shared text, shortened, for a title.
String titleOfText(String text, {int max = 100}) {
  final line = text.trim().split('\n').first.trim();
  return line.length > max ? '${line.substring(0, max).trim()}…' : line;
}
