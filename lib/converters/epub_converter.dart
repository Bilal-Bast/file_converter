import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'text_utils.dart';

class EpubBook {
  const EpubBook({required this.title, required this.chapters});
  final String title;
  final List<String> chapters;

  String toPlainText() => '$title\n\n${chapters.join('\n\n\n')}\n';
}

/// Reads an EPUB (a ZIP of XHTML files) and returns its chapters, in
/// reading order, as plain text.
///
/// How EPUB works:
///   META-INF/container.xml -> points to the .opf file
///   .opf `<manifest>`        -> list of files (id -> href)
///   .opf `<spine>`           -> reading order (list of ids)
EpubBook parseEpub(Uint8List bytes, {String fallbackTitle = 'Untitled'}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('This is not a valid EPUB file.');
  }

  // Case-insensitive lookup: some EPUBs get the case of paths wrong.
  final entries = <String, ArchiveFile>{
    for (final f in archive.files)
      if (f.isFile) f.name.toLowerCase(): f,
  };
  Uint8List? read(String path) {
    final f = entries[path.toLowerCase()];
    return f == null ? null : zipEntryBytes(f);
  }

  XmlDocument readXml(Uint8List data) =>
      XmlDocument.parse(utf8.decode(data, allowMalformed: true));

  // 1. container.xml -> OPF path
  final container = read('META-INF/container.xml');
  if (container == null) {
    throw const FormatException(
        'Not a valid EPUB (META-INF/container.xml is missing).');
  }
  final opfPath = readXml(container)
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'rootfile')
      .map((e) => e.getAttribute('full-path'))
      .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
  if (opfPath == null) {
    throw const FormatException('EPUB has no package (.opf) file.');
  }

  final opfBytes = read(opfPath);
  if (opfBytes == null) {
    throw FormatException('EPUB package file not found: $opfPath');
  }
  final opf = readXml(opfBytes);
  final opfDir = p.posix.dirname(opfPath);
  final elements = opf.descendants.whereType<XmlElement>().toList();

  // 2. title
  final titleEl = elements.where((e) => e.name.local == 'title').firstOrNull;
  final title = (titleEl?.innerText.trim().isNotEmpty ?? false)
      ? titleEl!.innerText.trim()
      : fallbackTitle;

  // 3. manifest (id -> href, media type)
  final manifest = <String, (String href, String type)>{};
  for (final item in elements.where((e) => e.name.local == 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifest[id] = (href, item.getAttribute('media-type') ?? '');
    }
  }

  // 4. spine (reading order)
  var order = elements
      .where((e) => e.name.local == 'itemref')
      .map((e) => e.getAttribute('idref'))
      .whereType<String>()
      .toList();
  if (order.isEmpty) order = manifest.keys.toList(); // broken spine: fall back

  final chapters = <String>[];
  for (final id in order) {
    final entry = manifest[id];
    if (entry == null) continue;
    final (href, type) = entry;
    final isHtml = type.contains('html') ||
        RegExp(r'\.x?html?$', caseSensitive: false).hasMatch(href);
    if (!isHtml) continue;

    var cleanHref = href.split('#').first;
    try {
      cleanHref = Uri.decodeFull(cleanHref);
    } catch (_) {/* keep as-is */}
    final path = p.posix.normalize(p.posix.join(opfDir, cleanHref));

    final data = read(path);
    if (data == null) continue;
    final text = htmlToText(utf8.decode(data, allowMalformed: true));
    if (text.trim().isNotEmpty) chapters.add(text);
  }

  if (chapters.isEmpty) {
    final drm = read('META-INF/encryption.xml') != null;
    throw FormatException(drm
        ? 'No readable text found. This book looks DRM-protected.'
        : 'No readable text found in this EPUB.');
  }
  return EpubBook(title: title, chapters: chapters);
}
