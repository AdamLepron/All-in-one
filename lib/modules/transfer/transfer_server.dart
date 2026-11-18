import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../files/file_ops.dart';

/// A file offered for download.
class SharedFile {
  SharedFile(this.path, this.size);
  final String path;
  final int size;
  String get name => p.basename(path);
}

/// One transfer in progress or finished, shown in the activity list.
class TransferEvent {
  TransferEvent(
    this.name,
    this.bytes, {
    required this.upload,
    this.total,
    this.done = false,
  });
  final String name;
  int bytes;
  final bool upload;

  /// Known for downloads only.
  final int? total;
  bool done;
}

String _escape(String s) => const HtmlEscape().convert(s);

/// Removes any path, control characters and reserved names from a file
/// name sent by another device.
String safeFileName(String raw) {
  var name = raw
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '')
      .trim();
  while (name.startsWith('.')) {
    name = name.substring(1);
  }
  return name.isEmpty ? 'fichier' : name;
}

/// What the owner of this phone decides about files sent by another device.
enum UploadDecision { accept, acceptAll, refuse }

/// Asked before a file from another device is saved. [from] is the sender's
/// network address.
typedef UploadApproval = Future<UploadDecision> Function(
  String from,
  String fileName,
);

/// A small web server that lets any device on the same network, with or
/// without this app, fetch the shared files or send files to this phone
/// through a web page. Every address contains a random token, so only
/// people given the link or the QR code can use it.
class TransferServer {
  TransferServer({
    this.files = const [],
    this.receiveDir,
    this.approve,
    this.approvalTimeout = const Duration(seconds: 45),
    Random? random,
  }) : token = _newToken(random ?? Random.secure());

  /// When set, the first file of each sending device must be accepted by the
  /// owner; without it every upload is accepted (the link already is secret).
  final UploadApproval? approve;
  final Duration approvalTimeout;

  /// Devices the owner accepted everything from, for this session.
  final _trusted = <String>{};

  /// Files offered for download, or empty when only receiving.
  final List<SharedFile> files;

  /// Where uploads are saved, or null when only sending.
  final String? receiveDir;
  final String token;
  final events = <TransferEvent>[];
  final _changes = StreamController<void>.broadcast();

  /// Fires whenever [events] changes.
  Stream<void> get changes => _changes.stream;

  HttpServer? _server;
  int get port => _server!.port;
  bool get running => _server != null;

  static String _newToken(Random random) {
    const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
    return List.generate(
      10,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// Starts listening on every interface; [port] 0 picks a free one.
  Future<void> start({int port = 0, InternetAddress? address}) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
    );
    _server = server;
    server.listen(_handle, onError: (Object _) {});
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    await _changes.close();
  }

  /// Addresses other devices can use, one per network interface.
  static Future<List<String>> localAddresses() async {
    final result = <String>[];
    for (final i in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      for (final a in i.addresses) {
        if (!a.isLoopback && !a.address.startsWith('169.254.')) {
          result.add(a.address);
        }
      }
    }
    return result;
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.isEmpty || segments.first != token) {
        response.statusCode = HttpStatus.notFound;
        response.write('Lien invalide');
        return;
      }
      final rest = segments.skip(1).toList();
      if (request.method == 'GET' && rest.isEmpty) {
        response.headers.contentType = ContentType.html;
        response.write(_page());
      } else if (request.method == 'GET' &&
          rest.length == 2 &&
          rest.first == 'f') {
        await _download(request, int.tryParse(rest[1]));
      } else if (request.method == 'POST' &&
          rest.length == 1 &&
          rest.first == 'up') {
        await _upload(request);
      } else {
        response.statusCode = HttpStatus.notFound;
      }
    } on Object {
      // A connection dropped halfway: nothing to report to anyone.
      try {
        response.statusCode = HttpStatus.internalServerError;
      } on Object {
        // Headers already sent.
      }
    } finally {
      await response.close().catchError((Object _) => response);
    }
  }

  Future<void> _download(HttpRequest request, int? index) async {
    final response = request.response;
    if (index == null || index < 0 || index >= files.length) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    final file = files[index];
    final event = TransferEvent(file.name, 0, upload: false, total: file.size);
    events.insert(0, event);
    _notify();
    response.headers
      ..contentType = ContentType.parse(
        lookupMimeType(file.path) ?? 'application/octet-stream',
      )
      ..set(
        HttpHeaders.contentDisposition,
        "attachment; filename*=UTF-8''${Uri.encodeComponent(file.name)}",
      );
    response.contentLength = file.size;
    var lastNotified = 0;
    try {
      await response.addStream(
        File(file.path).openRead().map((chunk) {
          event.bytes += chunk.length;
          if (event.bytes - lastNotified > 256 * 1024) {
            lastNotified = event.bytes;
            _notify();
          }
          return chunk;
        }),
      );
      event.done = event.bytes >= file.size;
    } finally {
      _notify();
    }
  }

  Future<void> _upload(HttpRequest request) async {
    final response = request.response;
    final dir = receiveDir;
    final boundary = request.headers.contentType?.parameters['boundary'];
    if (dir == null || boundary == null) {
      response.statusCode = dir == null
          ? HttpStatus.notFound
          : HttpStatus.badRequest;
      return;
    }
    await Directory(dir).create(recursive: true);
    var saved = 0;
    var refused = false;
    final from = request.connectionInfo?.remoteAddress.address ?? '?';
    await for (final part in request.cast<List<int>>().transform(
      MimeMultipartTransformer(boundary),
    )) {
      final disposition = part.headers['content-disposition'] ?? '';
      final match = RegExp(r'filename="([^"]*)"').firstMatch(disposition);
      if (match == null) {
        await part.drain<void>();
        continue;
      }
      final name = _decodeFileName(match.group(1)!);
      if (name.isEmpty) {
        await part.drain<void>(); // empty file field of the form
        continue;
      }
      if (refused) {
        await part.drain<void>();
        continue;
      }
      final ask = approve;
      if (ask != null && !_trusted.contains(from)) {
        UploadDecision decision;
        try {
          decision = await ask(
            from,
            safeFileName(name),
          ).timeout(approvalTimeout);
        } on Object {
          // No answer in time: treated as a refusal.
          decision = UploadDecision.refuse;
        }
        if (decision == UploadDecision.refuse) {
          refused = true;
          await part.drain<void>();
          continue;
        }
        if (decision == UploadDecision.acceptAll) _trusted.add(from);
      }
      final target = await uniquePath(dir, safeFileName(name));
      final event = TransferEvent(p.basename(target), 0, upload: true);
      events.insert(0, event);
      _notify();
      final sink = File(target).openWrite();
      try {
        await for (final chunk in part) {
          sink.add(chunk);
          event.bytes += chunk.length;
          if (event.bytes % (256 * 1024) < chunk.length) _notify();
        }
        event.done = true;
        saved++;
      } finally {
        await sink.close();
        _notify();
      }
    }
    response.headers.contentType = ContentType.html;
    if (refused && saved == 0) {
      response.statusCode = HttpStatus.forbidden;
      response.write(_refusedHtml());
    } else {
      response.write(_doneHtml(saved));
    }
  }

  String _refusedHtml() =>
      '<!doctype html><html lang="fr"><meta charset="utf-8">$_style<body><h1>Envoi refusé</h1><p>Le propriétaire du téléphone n\'a pas accepté ces fichiers.</p><p><a href="/$token/">Réessayer</a></p></body></html>';

  /// Browsers send non-ASCII names as raw UTF-8 bytes read as Latin-1.
  String _decodeFileName(String raw) {
    try {
      return utf8.decode(latin1.encode(raw));
    } on Object {
      return raw;
    }
  }

  static const _style = '''
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body{font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;padding:20px;background:#f7f7fb;color:#1c1c22}
h1{font-size:22px}a.f{display:block;padding:14px 16px;margin:10px 0;background:#fff;border-radius:14px;text-decoration:none;color:#1c1c22;border:1px solid #e3e3ec}
a.f small{display:block;color:#6b6b78;margin-top:2px}
button,input[type=file]{font-size:16px}button{padding:14px 22px;border:0;border-radius:24px;background:#5b5bd6;color:#fff;margin-top:14px}
.box{background:#fff;border:1px solid #e3e3ec;border-radius:14px;padding:18px}
</style>''';

  String _page() {
    final buffer = StringBuffer(
      '<!doctype html><html lang="fr"><meta charset="utf-8">$_style<title>All-in-One</title><body>',
    );
    if (files.isNotEmpty) {
      buffer.write('<h1>Fichiers à télécharger</h1>');
      for (var i = 0; i < files.length; i++) {
        buffer.write(
          '<a class="f" href="/$token/f/$i">${_escape(files[i].name)}<small>${_size(files[i].size)}</small></a>',
        );
      }
    }
    if (receiveDir != null) {
      buffer.write(
        '<h1>Envoyer des fichiers vers ce téléphone</h1><form class="box" method="post" action="/$token/up" enctype="multipart/form-data"><input type="file" name="f" multiple required><br><button type="submit">Envoyer</button></form>',
      );
    }
    buffer.write('</body></html>');
    return buffer.toString();
  }

  String _doneHtml(int count) =>
      '<!doctype html><html lang="fr"><meta charset="utf-8">$_style<body><h1>Envoyé ✓</h1><p>$count fichier${count > 1 ? 's' : ''} reçu${count > 1 ? 's' : ''}.</p><p><a href="/$token/">Envoyer d\'autres fichiers</a></p></body></html>';

  static String _size(int bytes) {
    if (bytes < 1000) return '$bytes o';
    if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(0)} ko';
    if (bytes < 1000000000) return '${(bytes / 1000000).toStringAsFixed(1)} Mo';
    return '${(bytes / 1000000000).toStringAsFixed(2)} Go';
  }

  /// Address to open on the other device.
  String urlFor(String address) => 'http://$address:$port/$token/';
}
