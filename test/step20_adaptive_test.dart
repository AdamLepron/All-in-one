import 'package:all_in_one/core/adaptive.dart';
import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/shell/app_shell.dart';
import 'package:all_in_one/modules/clock/clock_controller.dart';
import 'package:all_in_one/modules/files/files_ui.dart';
import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/recorder/recorder_controller.dart';
import 'package:all_in_one/modules/scanner/scan_store.dart';
import 'package:all_in_one/modules/music/music_controller.dart';
import 'package:all_in_one/modules/notes/notes_store.dart';
import 'package:all_in_one/modules/tasks/organizer_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('content width is capped; the rail starts on wide windows', () {
    expect(contentWidth(400), 400);
    expect(contentWidth(1600), maxContentWidth);
    expect(useRail(411), isFalse);
    expect(useRail(719), isFalse);
    expect(useRail(800), isTrue);
    expect(useRail(2000), isTrue);
  });

  test('columns grow with the width within their limits', () {
    expect(columnsFor(300, 170), 2);
    expect(columnsFor(600, 170), 3);
    expect(columnsFor(1000, 170), 5);
    expect(columnsFor(5000, 170), 8);
    expect(columnsFor(300, 170, min: 4), 4);
    expect(columnsFor(0, 100), 2);
  });

  Future<void> show(WidgetTester tester, Size size) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    late NotesStore notes;
    late OrganizerStore organizer;
    await tester.runAsync(() async {
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/ad_notes.db',
      );
      await databaseFactory.deleteDatabase(
        '${await getDatabasesPath()}/ad_org.db',
      );
      notes = await NotesStore.open(file: 'ad_notes.db');
      organizer = await OrganizerStore.load(file: 'ad_org.db');
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: notes),
          ChangeNotifierProvider.value(value: organizer),
          ChangeNotifierProvider.value(value: MusicController(settings)),
          ChangeNotifierProvider(create: (_) => MediaLibrary()),
          ChangeNotifierProvider(
            create: (_) =>
                RecorderController(directory: () async => '/tmp/ad_rec'),
          ),
          ChangeNotifierProvider(
            create: (_) => ScanStore(directory: () async => '/tmp/ad_scans'),
          ),
          ChangeNotifierProvider(create: (_) => ClockController()),
          ChangeNotifierProvider(create: (_) => FilesClipboard()),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pump();
  }

  testWidgets('a phone keeps the bottom bar', (tester) async {
    await show(tester, const Size(411, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tablet gets a side rail and can still switch tabs', (
    tester,
  ) async {
    await show(tester, const Size(1000, 700));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('Outils'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
