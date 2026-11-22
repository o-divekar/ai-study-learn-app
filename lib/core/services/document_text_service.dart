import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class DocumentTextService {
  static const supportedTextTypes = {
    'txt', 'md', 'csv', 'docx',
  };

  static String extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    return index < 0 ? '' : fileName.substring(index + 1).toLowerCase();
  }

  Future<String> extractText(String path, String fileType) async {
    final file = File(path);

    if (!await file.exists()) {
      throw StateError('The document is no longer available.');
    }

    String text;

    try {
      if (fileType == 'docx') {
        text = await _readDocx(file);
      } else if (supportedTextTypes.contains(fileType)) {
        // Plain-text formats must use UTF-8.
        text = utf8.decode(await file.readAsBytes());
      } else {
        throw StateError(
          'AI text extraction is not supported for this format yet.',
        );
      }
    } on FormatException {
      throw StateError(
        'The document could not be decoded. For text files, '
        'save a UTF-8 copy. For Word files, use a valid DOCX file.',
      );
    }

    text = text
        .replaceAll('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .trim();

    if (text.isEmpty) {
      throw StateError(
        'No readable text was found. Images and scanned content '
        'require OCR.',
      );
    }

    if (utf8.encode(text).length > 700000) {
      throw StateError(
        'This document contains too much text for the current '
        'summary workflow. Please select a shorter document.',
      );
    }

    return text;
  }

  Future<String> _readDocx(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());

    final document = archive.findFile('word/document.xml');

    if (document == null || !document.isFile) {
      throw StateError('This file is not a supported DOCX document.');
    }

    // Limit the XML part before parsing it.
    if (document.size > 5 * 1024 * 1024) {
      throw StateError(
        'This Word document is too large to process on this device.',
      );
    }

    final xml = XmlDocument.parse(
      utf8.decode(document.content),
    );

    final paragraphs = <String>[];

    for (final element in xml.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'p') continue;

      final buffer = StringBuffer();

      for (final node in element.descendants.whereType<XmlElement>()) {
        switch (node.name.local) {
          case 't':
            buffer.write(node.innerText);
            break;
          case 'tab':
            buffer.write('\t');
            break;
          case 'br':
          case 'cr':
            buffer.write('\n');
            break;
        }
      }

      final paragraph = buffer.toString().trim();
      if (paragraph.isNotEmpty) paragraphs.add(paragraph);
    }

    return paragraphs.join('\n\n');
  }
}