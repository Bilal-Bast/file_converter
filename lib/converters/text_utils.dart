import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Bytes of a file inside a ZIP (works with archive 3.x and 4.x).
Uint8List zipEntryBytes(ArchiveFile file) {
  final dynamic content = file.content;
  if (content is Uint8List) return content;
  return Uint8List.fromList(List<int>.from(content as Iterable));
}

/// Decodes a text file: UTF-8 (with/without BOM) or UTF-16 with BOM.
String decodeText(Uint8List b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xFE) return _utf16(b, 2, little: true);
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) return _utf16(b, 2, little: false);
  var s = utf8.decode(b, allowMalformed: true);
  if (s.startsWith('﻿')) s = s.substring(1);
  return s;
}

String _utf16(Uint8List b, int start, {required bool little}) {
  final units = <int>[];
  for (var i = start; i + 1 < b.length; i += 2) {
    units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

const _blockTags = {
  'p', 'div', 'section', 'article', 'header', 'footer', 'aside', 'nav',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', 'dl', 'dt', 'dd',
  'blockquote', 'pre', 'table', 'tr', 'hr', 'figure', 'figcaption',
};

/// Converts an (X)HTML chapter into readable plain text.
String htmlToText(String source) {
  final document = html_parser.parse(source);
  final root = document.body ?? document.documentElement;
  if (root == null) return '';

  final buffer = StringBuffer();
  void walk(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.text);
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName?.toLowerCase();
    if (tag == 'script' || tag == 'style' || tag == 'head') return;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    final isBlock = _blockTags.contains(tag);
    if (isBlock) buffer.write('\n');
    if (tag == 'li') buffer.write('• ');
    if (tag == 'td' || tag == 'th') buffer.write(' ');
    for (final child in node.nodes) {
      walk(child);
    }
    if (isBlock) buffer.write('\n');
  }

  walk(root);
  return normalizeText(buffer.toString());
}

/// Trims lines and keeps at most one blank line in a row.
/// [collapseSpaces] also squeezes runs of spaces/tabs (good for HTML).
String normalizeText(String s, {bool collapseSpaces = true}) {
  final spaces = RegExp(r'[ \t ]+');
  final lines = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final out = <String>[];
  var lastBlank = true;
  for (var line in lines) {
    line = collapseSpaces ? line.replaceAll(spaces, ' ').trim() : line.trimRight();
    if (line.trim().isEmpty) {
      if (!lastBlank) out.add('');
      lastBlank = true;
    } else {
      out.add(line);
      lastBlank = false;
    }
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}
