import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../converters/docx_converter.dart';
import '../converters/epub_converter.dart';
import '../converters/image_converter.dart';
import '../converters/pdf_builder.dart';
import '../converters/text_utils.dart';
import '../models.dart';

class ConversionService {
  Uint8List? _font;

  Future<Uint8List> _fontBytes() async {
    if (_font != null) return _font!;
    final data = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
    return _font = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// Converts files one at a time. Heavy work runs in a background isolate
  /// so the UI never freezes.
  Future<List<ConversionResult>> convert(
    List<InputFile> files,
    OutputFormat target, {
    bool mergeImagesToPdf = false,
    void Function(int done, int total)? onProgress,
  }) async {
    final font = await _fontBytes();
    final results = <ConversionResult>[];
    final usedNames = <String>{};

    String uniqueName(String base, String ext) {
      var name = '$base.$ext';
      for (var i = 2; usedNames.contains(name.toLowerCase()); i++) {
        name = '$base ($i).$ext';
      }
      usedNames.add(name.toLowerCase());
      return name;
    }

    final merge = mergeImagesToPdf &&
        target == OutputFormat.pdf &&
        files.length > 1 &&
        files.every((f) => f.kind == InputKind.image);

    if (merge) {
      onProgress?.call(0, 1);
      try {
        final bytes = await _runMerge(files);
        final base = '${p.basenameWithoutExtension(files.first.name)}_and_${files.length - 1}_more';
        results.add(ConversionResult.success(
          '${files.length} images',
          ConvertedFile(name: uniqueName(base, 'pdf'), bytes: bytes, format: OutputFormat.pdf),
        ));
      } catch (e) {
        results.add(ConversionResult.failure('${files.length} images', _message(e)));
      }
      onProgress?.call(1, 1);
      return results;
    }

    for (var i = 0; i < files.length; i++) {
      onProgress?.call(i, files.length);
      final file = files[i];
      try {
        final bytes = await _runOne(file, target, font);
        final name = uniqueName(p.basenameWithoutExtension(file.name), target.extension);
        results.add(ConversionResult.success(
          file.name,
          ConvertedFile(name: name, bytes: bytes, format: target),
        ));
      } catch (e) {
        results.add(ConversionResult.failure(file.name, _message(e)));
      }
    }
    onProgress?.call(files.length, files.length);
    return results;
  }

  // Static wrappers: the closure only captures its parameters, so nothing
  // from the UI gets sent to the background isolate.
  static Future<Uint8List> _runOne(InputFile f, OutputFormat t, Uint8List font) =>
      Isolate.run(() => _convertOne(f, t, font));

  static Future<Uint8List> _runMerge(List<InputFile> files) =>
      Isolate.run(() => _mergeImages(files));

  static String _message(Object e) => e is FormatException ? e.message : e.toString();
}

// ---- These run inside a background isolate (top-level = safe to send). ----

Future<Uint8List> _convertOne(InputFile file, OutputFormat target, Uint8List font) async {
  final base = p.basenameWithoutExtension(file.name);

  switch (file.kind) {
    case InputKind.epub:
      final book = parseEpub(file.bytes, fallbackTitle: base);
      if (target == OutputFormat.txt) {
        return Uint8List.fromList(utf8.encode(book.toPlainText()));
      }
      return buildTextPdf(title: book.title, sections: book.chapters, fontBytes: font);

    case InputKind.docx:
      final text = docxToText(file.bytes);
      if (target == OutputFormat.txt) return Uint8List.fromList(utf8.encode('$text\n'));
      return buildTextPdf(title: base, sections: [text], fontBytes: font, showTitle: false);

    case InputKind.txt:
      final text = normalizeText(decodeText(file.bytes), collapseSpaces: false);
      if (text.trim().isEmpty) throw const FormatException('This text file is empty.');
      return buildTextPdf(title: base, sections: [text], fontBytes: font, showTitle: false);

    case InputKind.image:
      final image = decodeAnyImage(file.bytes);
      if (target == OutputFormat.pdf) {
        return buildImagesPdf([_toPdfImage(image)], title: base);
      }
      return encodeImage(image, target);
  }
}

Future<Uint8List> _mergeImages(List<InputFile> files) async {
  final pages = <PdfImageInput>[];
  for (final f in files) {
    pages.add(_toPdfImage(decodeAnyImage(f.bytes)));
  }
  return buildImagesPdf(pages);
}

PdfImageInput _toPdfImage(img.Image image) {
  final jpg = encodeImage(image, OutputFormat.jpg);
  return PdfImageInput(jpg, image.width, image.height);
}
