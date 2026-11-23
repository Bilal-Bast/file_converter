import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// What kind of file the user picked.
enum InputKind { epub, docx, txt, image }

/// Formats the app can produce.
enum OutputFormat {
  txt('TXT', 'txt', 'text/plain'),
  pdf('PDF', 'pdf', 'application/pdf'),
  jpg('JPG', 'jpg', 'image/jpeg'),
  png('PNG', 'png', 'image/png'),
  bmp('BMP', 'bmp', 'image/bmp');

  const OutputFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'tif', 'tiff'};

String extensionOf(String fileName) =>
    p.extension(fileName).toLowerCase().replaceFirst('.', '');

InputKind? inputKindOf(String fileName) {
  final ext = extensionOf(fileName);
  if (ext == 'epub') return InputKind.epub;
  if (ext == 'docx') return InputKind.docx;
  if (ext == 'txt') return InputKind.txt;
  if (imageExtensions.contains(ext)) return InputKind.image;
  return null;
}

/// Which outputs make sense for each input kind.
/// To add a new conversion: add the target here, then handle it in
/// `conversion_service.dart`.
List<OutputFormat> targetsFor(InputKind kind) => switch (kind) {
      InputKind.epub => [OutputFormat.txt, OutputFormat.pdf],
      InputKind.docx => [OutputFormat.txt, OutputFormat.pdf],
      InputKind.txt => [OutputFormat.pdf],
      InputKind.image => [
          OutputFormat.jpg,
          OutputFormat.png,
          OutputFormat.bmp,
          OutputFormat.pdf,
        ],
    };

/// Output formats shared by every file in [files] (keeps the usual order).
List<OutputFormat> commonTargets(List<InputFile> files) {
  if (files.isEmpty) return const [];
  return OutputFormat.values
      .where((f) => files.every((file) => targetsFor(file.kind).contains(f)))
      .toList();
}

class InputFile {
  const InputFile({required this.name, required this.bytes, required this.kind});
  final String name;
  final Uint8List bytes;
  final InputKind kind;
}

class ConvertedFile {
  const ConvertedFile({required this.name, required this.bytes, required this.format});
  final String name;
  final Uint8List bytes;
  final OutputFormat format;
}

class ConversionResult {
  const ConversionResult.success(this.sourceName, ConvertedFile this.output) : error = null;
  const ConversionResult.failure(this.sourceName, String this.error) : output = null;

  final String sourceName;
  final ConvertedFile? output;
  final String? error;

  bool get ok => output != null;
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
