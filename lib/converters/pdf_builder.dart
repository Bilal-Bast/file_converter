import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Hebrew / Arabic ranges: paragraphs containing these are laid out right-to-left.
final _rtlChars = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');

/// Builds a text PDF. Each section (e.g. an EPUB chapter) starts on a new page.
/// [fontBytes] must be a TTF with the needed glyphs (we bundle DejaVu Sans,
/// which covers Latin, Arabic, Greek and Cyrillic).
Future<Uint8List> buildTextPdf({
  required String title,
  required List<String> sections,
  required Uint8List fontBytes,
  bool showTitle = true,
}) async {
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final doc = pw.Document(title: title, creator: 'File Converter');

  final widgets = <pw.Widget>[];
  if (showTitle) {
    widgets.add(pw.Header(
      level: 0,
      child: pw.Text(title, style: const pw.TextStyle(fontSize: 20)),
    ));
  }

  for (var i = 0; i < sections.length; i++) {
    if (i > 0) widgets.add(pw.NewPage());
    for (final paragraph in sections[i].split('\n')) {
      if (paragraph.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }
      final rtl = _rtlChars.hasMatch(paragraph);
      // Text is added directly (not wrapped) so very long paragraphs can
      // continue onto the next page.
      widgets.add(pw.Text(
        paragraph.replaceAll('\t', '    '),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
      ));
      widgets.add(pw.SizedBox(height: 4));
    }
  }

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 48, vertical: 40),
    maxPages: 100000, // default is only 20 pages, too small for books
    theme: pw.ThemeData.withFont(
            base: font, bold: font, italic: font, boldItalic: font)
        .copyWith(
            defaultTextStyle:
                pw.TextStyle(font: font, fontSize: 11, lineSpacing: 2)),
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
    ),
    build: (context) => widgets,
  ));

  return doc.save();
}

class PdfImageInput {
  const PdfImageInput(this.jpgBytes, this.width, this.height);
  final Uint8List jpgBytes;
  final int width;
  final int height;
}

/// One image per A4 page (landscape pages for wide images).
Future<Uint8List> buildImagesPdf(List<PdfImageInput> images,
    {String title = 'Images'}) async {
  final doc = pw.Document(title: title, creator: 'File Converter');
  for (final image in images) {
    final format = image.width > image.height
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final provider = pw.MemoryImage(image.jpgBytes);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(20),
      build: (_) =>
          pw.Center(child: pw.Image(provider, fit: pw.BoxFit.contain)),
    ));
  }
  return doc.save();
}
