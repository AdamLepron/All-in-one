import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'core/settings.dart';
import 'core/theme.dart';
import 'modules/notes/notes_store.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  final notes = await NotesStore.open();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: notes),
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
      darkTheme: buildTheme(settings.accent, Brightness.dark, amoled: settings.amoled),
      home: const AppShell(),
    );
  }
}
