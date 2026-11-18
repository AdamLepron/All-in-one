import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Sharpness of a picture given as RGBA pixels: the variance of its
/// Laplacian (how strongly neighbouring pixels differ). Sharp pictures have
/// many edges and score high; blurred ones are smooth and score low.
double laplacianVariance(Uint8List rgba, int width, int height) {
  if (width < 3 || height < 3) return double.infinity;
  // Grey levels first.
  final grey = Float64List(width * height);
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    grey[i] = 0.299 * rgba[o] + 0.587 * rgba[o + 1] + 0.114 * rgba[o + 2];
  }
  var sum = 0.0, sumSq = 0.0;
  var n = 0;
  for (var y = 1; y < height - 1; y++) {
    for (var x = 1; x < width - 1; x++) {
      final i = y * width + x;
      final lap =
          grey[i - width] +
          grey[i + width] +
          grey[i - 1] +
          grey[i + 1] -
          4 * grey[i];
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  final mean = sum / n;
  return sumSq / n - mean * mean;
}

/// Pictures scoring below this (on a 256-pixel-wide version) look blurred.
const blurThreshold = 35.0;

/// Sharpness score of the picture at [path], or null when it cannot be
/// read. The picture is decoded at a small size, so this stays quick.
Future<double?> blurScoreOfFile(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return laplacianVariance(
        data.buffer.asUint8List(),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
      codec.dispose();
    }
  } on Object {
    return null;
  }
}
