import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import 'file_ops.dart';

/// Icon and tint for each kind of file.
(IconData, Color) kindStyle(FileKind kind) => switch (kind) {
  FileKind.folder => (Icons.folder_rounded, const Color(0xFFF5A524)),
  FileKind.image => (Icons.image_rounded, const Color(0xFFD6409F)),
  FileKind.video => (Icons.movie_rounded, const Color(0xFFE5484D)),
  FileKind.audio => (Icons.music_note_rounded, const Color(0xFF8E4EC6)),
  FileKind.document => (Icons.description_rounded, const Color(0xFF0A84FF)),
  FileKind.archive => (Icons.folder_zip_rounded, const Color(0xFF978365)),
  FileKind.apk => (Icons.android_rounded, const Color(0xFF30A46C)),
  FileKind.other => (Icons.insert_drive_file_rounded, const Color(0xFF8B8D98)),
};

class KindIcon extends StatelessWidget {
  const KindIcon(this.kind, {super.key, this.size = 44});
  final FileKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = kindStyle(kind);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// Paths waiting to be pasted, shared by every folder screen.
class FilesClipboard extends ChangeNotifier {
  List<String> paths = const [];
  bool move = false;

  bool get isEmpty => paths.isEmpty;

  void set(List<String> items, {required bool move}) {
    paths = items;
    this.move = move;
    notifyListeners();
  }

  void clear() {
    paths = const [];
    notifyListeners();
  }
}

void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: action,
        duration: Duration(seconds: action == null ? 3 : 5),
      ),
    );
}

/// Asks for a name; returns null when cancelled or left empty.
Future<String?> askName(
  BuildContext context, {
  required String title,
  String initial = '',
  String action = 'OK',
}) {
  final controller = TextEditingController(text: initial);
  // Preselect the name without its extension.
  final dot = initial.lastIndexOf('.');
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: dot > 0 ? dot : initial.length,
  );
  return showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(dialog, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, controller.text),
          child: Text(action),
        ),
      ],
    ),
  ).then((value) {
    final name = value?.trim() ?? '';
    return name.isEmpty || name.contains('/') ? null : name;
  });
}

/// Makes sure the app may move and delete any file, explaining why before
/// the system screen opens. Returns false when access is refused.
Future<bool> ensureFullFileAccess(BuildContext context) async {
  try {
    if (await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted) {
      return true;
    }
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Accès aux fichiers'),
        content: const Text(
          "Pour déplacer un élément dans la corbeille, l'application a besoin de l'accès à tous les fichiers. Android va ouvrir l'écran d'autorisation.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    return await Permission.storage.request().isGranted;
  } on MissingPluginException {
    return true; // not on a device (tests)
  }
}
