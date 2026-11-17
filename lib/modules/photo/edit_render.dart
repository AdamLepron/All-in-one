import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

import 'edit_model.dart';

/// Reads [path] and decodes it with its longest side at most [maxSide].
/// EXIF orientation is applied by the decoder.
Future<ui.Image> loadPhoto(String path, {required int maxSide}) async {
  final bytes = await File(path).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final longest = math.max(descriptor.width, descriptor.height);
    final scale = longest > maxSide ? maxSide / longest : 1.0;
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    return frame.image;
  } finally {
    buffer.dispose();
  }
}

/// Size in pixels of the visible part of [image] once edited.
Size outputSize(ui.Image image, EditState s, {bool applyCrop = true}) {
  final o = orientedSize(image.width.toDouble(), image.height.toDouble(), s);
  if (!applyCrop) return o;
  return Size(
    math.max(1, (s.crop.width * o.width).roundToDouble()),
    math.max(1, (s.crop.height * o.height).roundToDouble()),
  );
}

/// Draws the edited photo at its natural size, from (0, 0) to
/// [outputSize]. Callers scale the canvas for previews.
void renderEdit(
  Canvas canvas,
  ui.Image image,
  EditState s, {
  bool applyCrop = true,
}) {
  final o = orientedSize(image.width.toDouble(), image.height.toDouble(), s);
  final out = outputSize(image, s, applyCrop: applyCrop);
  final origin = applyCrop
      ? Offset(s.crop.left * o.width, s.crop.top * o.height)
      : Offset.zero;

  canvas
    ..save()
    ..clipRect(Offset.zero & out)
    ..translate(-origin.dx, -origin.dy);

  // Photo: flip, then rotate, about the centre of the oriented picture.
  canvas
    ..save()
    ..translate(o.width / 2, o.height / 2)
    ..rotate(s.quarterTurns * math.pi / 2);
  if (s.flipped) canvas.scale(-1, 1);
  canvas.translate(-image.width / 2, -image.height / 2);
  final matrix = s.matrix;
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = matrix == identityMatrix
          ? null
          : ColorFilter.matrix(matrix),
  );
  canvas.restore();

  // Drawings, in oriented coordinates.
  final side = math.min(o.width, o.height);
  for (final stroke in s.strokes) {
    final paint = Paint()
      ..color = Color(stroke.color)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.width * side
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final pts = [
      for (final p in stroke.points) Offset(p.dx * o.width, p.dy * o.height),
    ];
    if (pts.length == 1) {
      canvas.drawCircle(
        pts.first,
        stroke.width * side / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  // Vignette darkens the edges of the visible frame.
  final vignette = s.value(Adjust.vignette) / 100;
  if (vignette > 0) {
    final frame = origin & out;
    canvas.drawRect(
      frame,
      Paint()
        ..shader = ui.Gradient.radial(
          frame.center,
          frame.size.longestSide * 0.72,
          [const Color(0x00000000), Color.fromRGBO(0, 0, 0, 0.75 * vignette)],
          [0.45, 1.0],
        ),
    );
  }
  canvas.restore();
}

/// Paints the edited photo scaled to fill the widget it is placed in.
class EditPainter extends CustomPainter {
  EditPainter(this.image, this.state, {this.applyCrop = true});
  final ui.Image image;
  final EditState state;
  final bool applyCrop;

  @override
  void paint(Canvas canvas, Size size) {
    final out = outputSize(image, state, applyCrop: applyCrop);
    canvas
      ..save()
      ..scale(size.width / out.width, size.height / out.height);
    renderEdit(canvas, image, state, applyCrop: applyCrop);
    canvas.restore();
  }

  @override
  bool shouldRepaint(EditPainter old) => true;
}

class EncodeJob {
  EncodeJob(this.width, this.height, this.rgba, this.quality);
  final int width;
  final int height;
  final TransferableTypedData rgba;
  final int quality;
}

Uint8List _encode(EncodeJob job) {
  final bytes = job.rgba.materialize().asUint8List();
  final image = img.Image.fromBytes(
    width: job.width,
    height: job.height,
    bytes: bytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: job.quality);
}

/// Renders [source] with [state] and returns it as JPEG bytes. Drawing runs
/// on the engine's raster thread and compression in a separate isolate, so
/// the interface stays responsive.
Future<Uint8List> exportJpeg(
  ui.Image source,
  EditState state, {
  int quality = 92,
}) async {
  final out = outputSize(source, state);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // JPEG has no transparency: paint on white.
  canvas.drawRect(Offset.zero & out, Paint()..color = const Color(0xFFFFFFFF));
  renderEdit(canvas, source, state);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(out.width.round(), out.height.round());
  picture.dispose();
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    final job = EncodeJob(
      rendered.width,
      rendered.height,
      TransferableTypedData.fromList([data!.buffer.asUint8List()]),
      quality,
    );
    return await Isolate.run(() => _encode(job));
  } finally {
    rendered.dispose();
  }
}

/// Where edited copies go.
const defaultOutputDir = '/storage/emulated/0/Pictures/All-in-One';

/// Opens [path] at full resolution (up to 4096 px), applies [state], and
/// saves the result as a new JPEG in [dir]. The original is never touched.
/// Returns the path of the new file.
Future<String> saveEditedCopy(
  String path,
  EditState state, {
  required String dir,
}) async {
  final source = await loadPhoto(path, maxSide: 4096);
  try {
    final bytes = await exportJpeg(source, state);
    await Directory(dir).create(recursive: true);
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    var target = '$dir/IMG_$stamp.jpg';
    for (var i = 1; File(target).existsSync(); i++) {
      target = '$dir/IMG_${stamp}_$i.jpg';
    }
    await File(target).writeAsBytes(bytes);
    return target;
  } finally {
    source.dispose();
  }
}
