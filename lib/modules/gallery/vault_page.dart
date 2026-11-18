import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../files/file_ops.dart';
import '../files/files_ui.dart';
import '../video/video_player_page.dart';
import 'media_library.dart';
import 'vault.dart';

/// Moves photos and videos out of the gallery into the protected folder.
/// Returns how many were moved.
Future<int> moveToVault(BuildContext context, List<Media> items) async {
  if (items.isEmpty) return 0;
  final settings = context.read<AppSettings>();
  final library = context.read<MediaLibrary>();
  final messenger = ScaffoldMessenger.of(context);
  if (!VaultLock(settings).hasPin) {
    showMessage(context, "Créez d'abord un code dans le dossier protégé");
    return 0;
  }
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('Déplacer vers le dossier protégé ?'),
      content: Text(
        '${items.length} élément${items.length > 1 ? 's' : ''} '
        'disparaîtr${items.length > 1 ? 'ont' : 'a'} de la galerie et '
        'ne se retrouver${items.length > 1 ? 'ont' : 'a'} que dans le dossier protégé.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Déplacer'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return 0;
  if (!await ensureFullFileAccess(context)) return 0;
  final vault = Vault();
  final moved = <Media>[];
  for (final m in items) {
    try {
      await vault.add(m.path, video: m.video);
      // Only once the copy is safe does the original go.
      await deleteForever(m.path);
      moved.add(m);
    } on Object {
      continue; // left in place
    }
  }
  if (moved.isNotEmpty) {
    await MediaChannel.rescan([for (final m in moved) m.path]);
    library.forget(moved);
  }
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          moved.isEmpty
              ? 'Déplacement impossible'
              : '${moved.length} élément${moved.length > 1 ? 's' : ''} dans le dossier protégé',
        ),
      ),
    );
  return moved.length;
}

/// The protected folder: asks for the code, then shows what is inside.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key, this.vault});
  final Vault? vault;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> with WidgetsBindingObserver {
  late final AppSettings _settings = context.read<AppSettings>();
  late final VaultLock _lock = VaultLock(_settings);
  late final Vault _vault = widget.vault ?? Vault();

  bool _unlocked = false;
  List<VaultItem> _items = const [];
  final _selected = <String>{};
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MediaChannel.secure(false);
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app closes the folder.
    if (state == AppLifecycleState.paused && _unlocked) {
      setState(() => _lockNow());
    }
  }

  void _lockNow() {
    _unlocked = false;
    _selected.clear();
    _code.clear();
    _confirm.clear();
    _message = null;
    MediaChannel.secure(false);
  }

  Future<void> _open() async {
    MediaChannel.secure(true);
    final items = await _vault.items();
    if (mounted) {
      setState(() {
        _unlocked = true;
        _items = items;
        _message = null;
        _code.clear();
        _confirm.clear();
      });
    }
  }

  Future<void> _reload() async {
    final items = await _vault.items();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _submitCode() async {
    final pin = _code.text;
    if (!_lock.hasPin) {
      if (!VaultLock.valid(pin)) {
        setState(() => _message = 'Le code doit avoir de 4 à 8 chiffres');
      } else if (pin != _confirm.text) {
        setState(() => _message = 'Les deux codes sont différents');
      } else {
        _lock.setPin(pin);
        await _open();
      }
      return;
    }
    switch (_lock.check(pin)) {
      case PinResult.ok:
        await _open();
      case PinResult.wrong:
        _code.clear();
        setState(
          () => _message =
              'Code incorrect · ${_lock.triesLeft} essai${_lock.triesLeft > 1 ? 's' : ''} restant${_lock.triesLeft > 1 ? 's' : ''}',
        );
      case PinResult.locked:
        _code.clear();
        final until = _lock.lockedUntil;
        setState(
          () => _message = until == null
              ? 'Trop d\'essais'
              : 'Trop d\'essais : réessayez à ${until.hour}:${until.minute.toString().padLeft(2, '0')}',
        );
    }
  }

  Future<void> _restore(List<VaultItem> items) async {
    final library = context.read<MediaLibrary>();
    if (!await ensureFullFileAccess(context)) return;
    final restored = <String>[];
    for (final i in items) {
      try {
        final dir = p.join(
          storageRoot,
          i.video ? 'Movies' : 'Pictures',
          'All-in-One',
        );
        restored.add(await _vault.restore(i, dir));
      } on Object {
        continue;
      }
    }
    if (restored.isNotEmpty) {
      await MediaChannel.rescan(restored);
      await library.load(request: false);
    }
    _selected.clear();
    await _reload();
    if (mounted) {
      showMessage(
        context,
        restored.isEmpty
            ? 'Restauration impossible'
            : '${restored.length} élément${restored.length > 1 ? 's' : ''} remis dans la galerie',
      );
    }
  }

  Future<void> _delete(List<VaultItem> items) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text('Cette action est irréversible.'),
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
    if (ok != true) return;
    for (final i in items) {
      await _vault.remove(i);
    }
    _selected.clear();
    await _reload();
  }

  Future<void> _changeCode() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Nouveau code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: const InputDecoration(hintText: '4 à 8 chiffres'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, controller.text),
            child: const Text('Changer'),
          ),
        ],
      ),
    );
    if (pin == null || !mounted) return;
    if (VaultLock.valid(pin)) {
      _lock.setPin(pin);
      showMessage(context, 'Code changé');
    } else {
      showMessage(context, 'Le code doit avoir de 4 à 8 chiffres');
    }
  }

  Future<void> _view(VaultItem item) async {
    final file = await _vault.fileOf(item);
    if (!mounted) return;
    if (item.video) {
      final media = Media(
        id: item.stored.hashCode.abs(),
        video: true,
        path: file.path,
        name: item.name,
        date: item.added,
        uri: Uri.file(file.path).toString(),
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => VideoPlayerPage(media: media)),
      );
      // The player leaves the window insecure settings alone; keep ours.
      MediaChannel.secure(true);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(item.name, style: const TextStyle(fontSize: 16)),
            ),
            body: InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.file(file)),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_unlocked) return _lockScreen(scheme);
    final selecting = _selected.isNotEmpty;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Annuler la sélection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selected.clear),
                ),
                title: Text('${_selected.length}'),
                actions: [
                  IconButton(
                    tooltip: 'Remettre dans la galerie',
                    icon: const Icon(Icons.unarchive_outlined),
                    onPressed: () => _restore([
                      for (final i in _items)
                        if (_selected.contains(i.stored)) i,
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Supprimer définitivement',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete([
                      for (final i in _items)
                        if (_selected.contains(i.stored)) i,
                    ]),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Dossier protégé'),
                actions: [
                  IconButton(
                    tooltip: 'Verrouiller',
                    icon: const Icon(Icons.lock_outline),
                    onPressed: () => setState(_lockNow),
                  ),
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Plus',
                    onSelected: (a) => a(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: _changeCode,
                        child: const Text('Changer le code'),
                      ),
                    ],
                  ),
                ],
              ),
        body: _items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 64, color: scheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'Le dossier est vide',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Dans la galerie, sélectionnez des photos puis « Déplacer vers le dossier protégé ». '
                        'Elles disparaissent de la galerie et des autres applications.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(4),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final item = _items[i];
                  final picked = _selected.contains(item.stored);
                  return FutureBuilder<File>(
                    future: _vault.fileOf(item),
                    builder: (_, snap) {
                      void toggle() => setState(() {
                        picked
                            ? _selected.remove(item.stored)
                            : _selected.add(item.stored);
                      });
                      return Semantics(
                        label:
                            '${item.video ? 'Vidéo' : 'Photo'} ${item.name}${picked ? ', sélectionnée' : ''}',
                        button: true,
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: selecting ? toggle : () => _view(item),
                          onLongPress: toggle,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (snap.data == null || item.video)
                                ColoredBox(
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(
                                    item.video
                                        ? Icons.play_circle_outline
                                        : Icons.image_outlined,
                                    size: 36,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              else
                                Image.file(
                                  snap.data!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              if (picked)
                                ColoredBox(
                                  color: scheme.primary.withValues(alpha: 0.45),
                                ),
                              if (picked)
                                const Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Widget _lockScreen(ColorScheme scheme) {
    final creating = !_lock.hasPin;
    final until = _lock.lockedUntil;
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier protégé')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text(
                  creating ? 'Choisissez un code' : 'Entrez votre code',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (creating)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Il protège les photos et vidéos que vous cacher ici. '
                      'Sans lui, elles ne peuvent pas être ouvertes : notez-le bien.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 20),
                TextField(
                  controller: _code,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  enabled: until == null,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  onSubmitted: (_) => creating ? null : _submitCode(),
                  decoration: InputDecoration(
                    hintText: creating ? '4 à 8 chiffres' : 'Code',
                  ),
                ),
                if (creating) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    onSubmitted: (_) => _submitCode(),
                    decoration: const InputDecoration(
                      hintText: 'Confirmez le code',
                    ),
                  ),
                ],
                if (_message != null || until != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _message ??
                          'Verrouillé jusqu\'à ${until!.hour}:${until.minute.toString().padLeft(2, '0')}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: until == null ? _submitCode : null,
                  child: Text(creating ? 'Créer le code' : 'Ouvrir'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
