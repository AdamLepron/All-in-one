import 'dart:io';

import 'package:all_in_one/modules/gallery/media_library.dart';
import 'package:all_in_one/modules/video_editor/video_editor_home.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

Future<void> loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  Future<ByteData> read(String name) async =>
      ByteData.sublistView(await File('$dir/$name').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Medium', 'Bold', 'Light']) {
    roboto.addFont(read('Roboto-$f.ttf'));
  }
  await roboto.load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(read('MaterialIcons-Regular.otf'))).load();
}

Media video(int id, int seconds) => Media(
  id: id,
  video: true,
  path: '/v/$id.mp4',
  name: 'VID_$id.mp4',
  date: DateTime(2026, 11, 17, 10, id),
  uri: 'content://media/external/video/media/$id',
  width: 1920,
  height: 1080,
  duration: Duration(seconds: seconds),
);

void main() {
  testWidgets('home lists the videos of the library', (tester) async {
    tester.view.physicalSize = const Size(824, 1784);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => MediaLibrary()..debugSet([video(1, 60), video(2, 20)]),
        child: const MaterialApp(home: VideoEditorHome()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Choisissez la première vidéo'), findsOneWidget);
    expect(find.byType(GridView), findsOneWidget);
  });
}
