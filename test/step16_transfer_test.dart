import 'dart:convert';
import 'dart:io';

import 'package:all_in_one/modules/transfer/transfer_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late TransferServer server;
  late HttpClient client;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('step16_transfer');
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await tmp.delete(recursive: true);
  });

  /// Sends the named files in one multipart request; returns status and body.
  Future<(int, String)> upload(
    String base,
    Map<String, List<int>> files,
  ) async {
    const boundary = '----b';
    final request = await client.postUrl(Uri.parse('$base/up'));
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    for (final e in files.entries) {
      request.add(
        utf8.encode(
          '--$boundary\r\nContent-Disposition: form-data; name="f"; filename="${e.key}"\r\n'
          'Content-Type: application/octet-stream\r\n\r\n',
        ),
      );
      request.add(e.value);
      request.add(utf8.encode('\r\n'));
    }
    request.add(utf8.encode('--$boundary--\r\n'));
    final response = await request.close();
    return (response.statusCode, await utf8.decodeStream(response));
  }

  Future<String> start({
    UploadApproval? approve,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    server = TransferServer(
      receiveDir: '${tmp.path}/recus',
      approve: approve,
      approvalTimeout: timeout,
    );
    await server.start(address: InternetAddress.loopbackIPv4);
    return 'http://127.0.0.1:${server.port}/${server.token}';
  }

  List<String> received() {
    final d = Directory('${tmp.path}/recus');
    return d.existsSync()
        ? d.listSync().map((e) => e.path.split('/').last).toList()
        : [];
  }

  test(
    'without an approval callback every upload is accepted (as before)',
    () async {
      final base = await start();
      final r = await upload(base, {
        'a.txt': [1, 2, 3],
      });
      expect(r.$1, 200);
      expect(received(), ['a.txt']);
    },
  );

  test('a refused file is not saved and the sender is told', () async {
    final asked = <String>[];
    final base = await start(
      approve: (from, name) async {
        asked.add('$from|$name');
        return UploadDecision.refuse;
      },
    );
    final r = await upload(base, {
      'photo.jpg': List.filled(5000, 9),
      'autre.jpg': [1],
    });
    expect(r.$1, 403);
    expect(r.$2, contains('Envoi refusé'));
    expect(received(), isEmpty);
    // Asked once for the whole request, not once per file.
    expect(asked, ['127.0.0.1|photo.jpg']);
    expect(server.events, isEmpty);
  });

  test('accept saves one file; the next request is asked again', () async {
    var asked = 0;
    final base = await start(
      approve: (from, name) async {
        asked++;
        return UploadDecision.accept;
      },
    );
    expect(
      (await upload(base, {
        '1.txt': [1],
      })).$1,
      200,
    );
    expect(
      (await upload(base, {
        '2.txt': [2],
      })).$1,
      200,
    );
    expect(asked, 2);
    expect(received()..sort(), ['1.txt', '2.txt']);
  });

  test('accept-all trusts that device for the rest of the session', () async {
    var asked = 0;
    final base = await start(
      approve: (from, name) async {
        asked++;
        return UploadDecision.acceptAll;
      },
    );
    expect(
      (await upload(base, {
        '1.txt': [1],
        '2.txt': [2],
      })).$1,
      200,
    );
    expect(
      (await upload(base, {
        '3.txt': [3],
      })).$1,
      200,
    );
    expect(asked, 1);
    expect(received()..sort(), ['1.txt', '2.txt', '3.txt']);
  });

  test('no answer in time counts as a refusal', () async {
    final base = await start(
      timeout: const Duration(milliseconds: 80),
      approve: (from, name) => Future<UploadDecision>.delayed(
        const Duration(seconds: 5),
        () => UploadDecision.accept,
      ),
    );
    final r = await upload(base, {
      'lent.txt': [1],
    });
    expect(r.$1, 403);
    expect(received(), isEmpty);
  });

  test('an error while asking refuses instead of saving', () async {
    final base = await start(
      approve: (from, name) async => throw StateError('boom'),
    );
    expect(
      (await upload(base, {
        'x.txt': [1],
      })).$1,
      403,
    );
    expect(received(), isEmpty);
  });

  test('names are still cleaned after approval', () async {
    final base = await start(
      approve: (from, name) async {
        expect(name, 'passwd'); // asked about the safe name, not the path
        return UploadDecision.accept;
      },
    );
    final r = await upload(base, {
      '../../etc/passwd': [1],
    });
    expect(r.$1, 200);
    expect(received(), ['passwd']);
  });
}
