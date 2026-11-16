import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/settings.dart';
import 'core/theme.dart';

import 'package:just_audio_background/just_audio_background.dart';

import 'modules/equalizer/equalizer_controller.dart';
import 'modules/files/files_ui.dart';
import 'modules/gallery/media_library.dart';
import 'modules/music/music_controller.dart';
import 'modules/notes/notes_store.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final notes = await NotesStore.open();
  // Media notification and lock-screen controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.allinone.all_in_one.audio',
    androidNotificationChannelName: 'Lecture audio',
    androidNotificationOngoing: true,
  );
  // Silent: reads the library only if access was already granted.
  final music = MusicController(settings)..loadLibrary(request: false);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: music),
        ChangeNotifierProvider(
          create: (_) => EqualizerController(settings, music),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => FilesClipboard()),
        ChangeNotifierProvider(
          create: (_) => MediaLibrary()..load(request: false),
        ),
      ],
      child: const AllInOneApp(),
    ),
  );
}

class AllInOneApp extends StatelessWidget {
  const AllInOneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    return MaterialApp(
      title: 'All-in-One',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(settings.accent, Brightness.light),
      darkTheme: buildTheme(
        settings.accent,
        Brightness.dark,
        amoled: settings.amoled,
      ),
      home: const AppShell(),
    );
  }
}
