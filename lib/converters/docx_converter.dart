import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'text_utils.dart';

/// Extracts plain text from a .docx (a ZIP containing word/document.xml).
///
/// In document.xml: `<w:p>` = paragraph, `<w:t>` = text, `<w:tab/>` = tab,
/// `<w:br/>` = line break. Deleted tracked-changes (`<w:delText>`) are skipped.
String docxToText(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException(
        'This is not a valid DOCX file. (Old .doc files are not supported.)');
  }
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw const FormatException('Not a valid DOCX file (word/document.xml is missing).');
  }

  final doc = XmlDocument.parse(utf8.decode(zipEntryBytes(entry), allowMalformed: true));
  final buffer = StringBuffer();

  void walk(XmlElement element) {
    for (final child in element.childElements) {
      switch (child.name.local) {
        case 't':
          buffer.write(child.innerText);
        case 'tab':
          buffer.write('\t');
        case 'br' || 'cr':
          buffer.write('\n');
        case 'p':
          walk(child);
          buffer.write('\n');
        case 'delText' || 'instrText':
          break; // deleted text / field codes
        default:
          walk(child);
      }
    }
  }

  walk(doc.rootElement);
  final text = normalizeText(buffer.toString(), collapseSpaces: false);
  if (text.trim().isEmpty) throw const FormatException('This document has no text.');
  return text;
}
