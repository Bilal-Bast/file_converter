import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models.dart';

/// Decodes JPG, PNG, WEBP, BMP, GIF (first frame) or TIFF and applies the
/// EXIF rotation so phone photos are not sideways.
img.Image decodeAnyImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not read this image (unsupported or damaged).');
  }
  return img.bakeOrientation(decoded);
}

/// Note: the `image` package can read WEBP but cannot write it.
Uint8List encodeImage(img.Image image, OutputFormat format, {int jpgQuality = 90}) {
  return switch (format) {
    OutputFormat.jpg => img.encodeJpg(flattenAlpha(image), quality: jpgQuality),
    OutputFormat.png => img.encodePng(image),
    OutputFormat.bmp => img.encodeBmp(image),
    _ => throw ArgumentError('Not an image format: $format'),
  };
}

/// JPG has no transparency: put the image on a white background so
/// transparent areas don't turn black.
img.Image flattenAlpha(img.Image src) {
  if (!src.hasAlpha) return src;
  final background = img.Image(width: src.width, height: src.height);
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(background, src);
}
