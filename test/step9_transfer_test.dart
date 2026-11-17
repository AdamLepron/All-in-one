import 'dart:convert';
import 'dart:io';

import 'package:all_in_one/modules/transfer/transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late TransferServer server;
  late HttpClient client;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('transfer_test');
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await tmp.delete(recursive: true);
  });

  Future<(int, String)> get(String url) async {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  test('files are served only under the secret link', () async {
    final photo = File('${tmp.path}/été & photo.jpg')
      ..writeAsBytesSync(List.filled(300000, 7));
    server = TransferServer(files: [SharedFile(photo.path, 300000)]);
    await server.start(address: InternetAddress.loopbackIPv4);
    final base = 'http://127.0.0.1:${server.port}';

    expect((await get('$base/')).$1, 404);
    expect((await get('$base/wrongtoken/')).$1, 404);
    expect((await get('$base/wrongtoken/f/0')).$1, 404);

    final page = await get('$base/${server.token}/');
    expect(page.$1, 200);
    expect(page.$2, contains('été &amp; photo.jpg')); // escaped
    expect(page.$2, contains('300 ko'));
    expect(
      page.$2,
      isNot(contains('type="file"')),
    ); // no upload form when only sending

    final request = await client.getUrl(Uri.parse('$base/${server.token}/f/0'));
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(
      response.headers.value('content-disposition'),
      contains("UTF-8''%C3%A9t%C3%A9"),
    );
    final bytes = await response.fold<int>(0, (n, c) => n + c.length);
    expect(bytes, 300000);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(server.events.single.done, true);
    expect(server.events.single.upload, false);

    expect((await get('$base/${server.token}/f/9')).$1, 404);
    expect((await get('$base/${server.token}/f/-1')).$1, 404);
    expect((await get('$base/${server.token}/up')).$1, 404);
  });

  test('uploads are saved safely and never overwrite', () async {
    final dir = '${tmp.path}/recus';
    server = TransferServer(receiveDir: dir);
    await server.start(address: InternetAddress.loopbackIPv4);
    final base = 'http://127.0.0.1:${server.port}/${server.token}';

    Future<int> upload(String filename, List<int> content) async {
      const boundary = '----testboundary';
      final request = await client.postUrl(Uri.parse('$base/up'));
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      final head = utf8.encode(
        '--$boundary\r\nContent-Disposition: form-data; name="f"; filename="$filename"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      );
      final tail = utf8.encode('\r\n--$boundary--\r\n');
      request.add([...head, ...content, ...tail]);
      return (await request.close()).statusCode;
    }

    expect(await upload('note.txt', utf8.encode('bonjour')), 200);
    expect(File('$dir/note.txt').readAsStringSync(), 'bonjour');
    // Same name again: kept as a second file.
    expect(await upload('note.txt', utf8.encode('second')), 200);
    expect(File('$dir/note (1).txt').readAsStringSync(), 'second');
    // Path tricks cannot leave the folder.
    expect(await upload('../../evil.txt', utf8.encode('x')), 200);
    expect(File('$dir/evil.txt').existsSync(), true);
    expect(File('${tmp.path}/evil.txt').existsSync(), false);
    // Binary content with boundary-like bytes survives intact.
    final binary = List.generate(200000, (i) => (i * 31) % 256);
    expect(await upload('data.bin', binary), 200);
    expect(File('$dir/data.bin').readAsBytesSync(), binary);
    // Browsers send UTF-8 names byte by byte; they must come out readable.
    expect(await upload(latin1.decode(utf8.encode('café.txt')), [65]), 200);
    expect(File('$dir/café.txt').existsSync(), true);

    final page = await (await client.getUrl(Uri.parse('$base/'))).close();
    expect(await utf8.decodeStream(page), contains('type="file"'));
    expect(server.events.where((e) => e.upload && e.done).length, 5);
  });

  test('file name sanitising', () {
    expect(safeFileName('../../etc/passwd'), 'passwd');
    expect(safeFileName(r'C:\Users\a\photo.png'), 'photo.png');
    expect(safeFileName('.hidden'), 'hidden');
    expect(safeFileName('a<b>:c|d?.txt'), 'abcd.txt');
    expect(safeFileName('   '), 'fichier');
  });

  test('tokens are random and long enough', () {
    final tokens = {for (var i = 0; i < 50; i++) TransferServer().token};
    expect(tokens.length, 50);
    expect(tokens.every((t) => t.length == 10), true);
    server = TransferServer();
  });
}
