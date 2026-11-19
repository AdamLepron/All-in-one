import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/adaptive.dart';
import 'core/crash_log.dart';
import 'core/l10n.dart';
import 'core/notifications.dart';
import 'core/settings.dart';
import 'core/theme.dart';

import 'package:just_audio_background/just_audio_background.dart';

import 'modules/clock/alarms.dart';
import 'modules/clock/clock_controller.dart';
import 'modules/equalizer/equalizer_controller.dart';
import 'modules/files/files_ui.dart';
import 'modules/gallery/media_library.dart';
import 'modules/music/music_controller.dart';
import 'modules/notes/notes_store.dart';
import 'modules/recorder/recorder_controller.dart';
import 'modules/scanner/scan_store.dart';
import 'modules/tasks/organizer_store.dart';
import 'modules/tasks/reminder_actions.dart';
import 'modules/ads/ads_controller.dart';
import 'shell/app_shell.dart';

/// What the native side noted about an earlier crash, if anything.
Future<String?> _readNativeCrash() async {
  try {
    return CrashLog.importNative(await getApplicationSupportDirectory());
  } on Object {
    return null;
  }
}

/// True when a native crash points at the ads, billing or their helpers.
bool _mentionsAds(String? trace) =>
    trace != null &&
    RegExp(
      'googlemobileads|gms\\.ads|billingclient|inapppurchase|androidx\\.work|webviewflutter',
      caseSensitive: false,
    ).hasMatch(trace);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashLog.init();
  CrashLog.install();
  // A crash the native side saw during an earlier launch goes to the journal.
  final nativeCrash = await _readNativeCrash();
  final settings = await AppSettings.load();
  final notes = await NotesStore.open();
  await Reminders.init(background: reminderBackground);
  final organizer = await OrganizerStore.load();
  // Not awaited: re-arming reminders must not delay the first frame.
  organizer.refreshReminders();
  final alarms = AlarmStore(settings);
  // Alarms are re-armed at every launch and one-time ones that rang are cleared.
  alarms.refresh();
  // Buttons of a reminder pressed while the app is open or in the background.
  Reminders.onAction = (action, payload) =>
      handleReminderAction(organizer, action, payload);
  // A reminder's button may have changed the database from another isolate.
  AppLifecycleListener(
    onResume: () {
      organizer.reload();
      alarms.refresh();
    },
  );
  // Media notification and lock-screen controls.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.wargheadstudio.allinone.audio',
    androidNotificationChannelName: 'Lecture audio',
    androidNotificationOngoing: true,
  );
  // Silent: reads the library only if access was already granted.
  final music = MusicController(settings)..loadLibrary(request: false);
  // Ads and the purchase that removes them: started without waiting, and
  // not at all for someone who already bought the removal.
  final ads = AdsController(settings, crashed: _mentionsAds(nativeCrash));
  // The ads start a few seconds after the screen is up, never during launch.
  Future<void>.delayed(const Duration(seconds: 4), ads.start);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: organizer),
        ChangeNotifierProvider.value(value: music),
        ChangeNotifierProvider.value(value: alarms),
        ChangeNotifierProvider.value(value: ads),
        ChangeNotifierProvider(
          create: (_) => EqualizerController(settings, music),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => FilesClipboard()),
        ChangeNotifierProvider(create: (_) => ClockController()),
        ChangeNotifierProvider(create: (_) => RecorderController()),
        ChangeNotifierProvider(create: (_) => ScanStore()..load()),
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
    // Chosen once per rebuild so every screen below speaks the same language.
    L10n.use(settings.language, PlatformDispatcher.instance.locale);
    return MaterialApp(
      locale: L10n.locale,
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      title: 'All-in-One',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: buildTheme(settings.accent, Brightness.light),
      darkTheme: buildTheme(
        settings.accent,
        Brightness.dark,
        amoled: settings.amoled,
      ),
      // On a tablet or a wide window the app stays at a comfortable width,
      // centred, instead of stretching lists and forms across the screen.
      builder: (context, child) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
      home: const AppShell(),
    );
  }
}
