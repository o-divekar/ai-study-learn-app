import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xls;
import 'package:xml/xml.dart';

import 'document_text_service.dart';
import 'pdf_service.dart';

enum ConversionType {
  pdfToWord,
  wordToPdf,
  wordTablesToExcel,
  textToPdf,
}

extension ConversionTypeInfo on ConversionType {
  String get label {
    switch (this) {
      case ConversionType.pdfToWord:
        return 'PDF → Word';
      case ConversionType.wordToPdf:
        return 'Word → PDF';
      case ConversionType.wordTablesToExcel:
        return 'Word tables → Excel';
      case ConversionType.textToPdf:
        return 'TXT → PDF';
    }
  }

  String get inputExtension {
    switch (this) {
      case ConversionType.pdfToWord:
        return 'pdf';
      case ConversionType.wordToPdf:
      case ConversionType.wordTablesToExcel:
        return 'docx';
      case ConversionType.textToPdf:
        return 'txt';
    }
  }

  String get outputExtension {
    switch (this) {
      case ConversionType.pdfToWord:
        return 'docx';
      case ConversionType.wordTablesToExcel:
        return 'xlsx';
      case ConversionType.wordToPdf:
      case ConversionType.textToPdf:
        return 'pdf';
    }
  }

  String get description {
    switch (this) {
      case ConversionType.pdfToWord:
        return 'Extracts editable text. Images, columns, and original '
            'formatting are not preserved. Scanned pages need OCR.';
      case ConversionType.wordToPdf:
        return 'Creates a simple text PDF from DOCX paragraphs. '
            'Images and original Word layout are not preserved.';
      case ConversionType.wordTablesToExcel:
        return 'Exports simple Word tables into separate worksheets. '
            'Merged or nested tables are not supported.';
      case ConversionType.textToPdf:
        return 'Creates a PDF from a UTF-8 text file.';
    }
  }
}

class DocumentConverterService {
    Future<File> exportReviewedTextPdf({
    required String text,
    required String ownerId,
  }) async {
    if (ownerId.trim().isEmpty) {
      throw StateError('Please sign in again.');
    }

    if (text.trim().isEmpty) {
      throw StateError('There is no reviewed text to export.');
    }

    final bytes = await _makePdf(
      'Reviewed text copy\n\n${text.trim()}',
    );

    final directory = await getApplicationDocumentsDirectory();

    final safeOwner = base64Url
        .encode(utf8.encode(ownerId))
        .replaceAll('=', '');

    final folder = Directory(
      '${directory.path}/reviewed_exports/$safeOwner',
    );

    await folder.create(recursive: true);

    final exportFolder = await folder.createTemp('export_');

    final output = File(
      '${exportFolder.path}/reviewed_text_copy.pdf',
    );

    await output.writeAsBytes(bytes, flush: true);

    return output;
  }
  Future<File> convert({
    required String path,
    required String fileName,
    required ConversionType type,
    required String ownerId,
  }) async {
    final input = File(path);

    if (!await input.exists()) {
      throw StateError('The selected file is no longer available.');
    }

    final size = await input.length();

    if (size == 0 || size > 10 * 1024 * 1024) {
      throw StateError('Choose a non-empty file smaller than 10 MB.');
    }

    if (DocumentTextService.extension(fileName) != type.inputExtension) {
      throw StateError(
        'Choose a .${type.inputExtension} file for this conversion.',
      );
    }

    late List<int> output;

    switch (type) {
      case ConversionType.pdfToWord:
        final pages = await PdfService().extractPages(path);

        if (pages.any((page) => !page.hasText)) {
          throw StateError(
            'Some pages have no readable text. They may be blank or '
            'scanned. This version stops to avoid silently omitting '
            'pages. Use a text-based PDF.',
          );
        }

        final text = pages.map((page) => page.text).join('\n\n');
        _checkTextSize(text);
        output = _makeDocx(text);
        break;

      case ConversionType.wordToPdf:
        final text = await DocumentTextService().extractText(
          path,
          'docx',
        );
        output = await _makePdf(text);
        break;

      case ConversionType.textToPdf:
        final text = await DocumentTextService().extractText(
          path,
          'txt',
        );
        output = await _makePdf(text);
        break;

      case ConversionType.wordTablesToExcel:
        output = await _tablesToExcel(input);
        break;
    }

    final directory = await getApplicationDocumentsDirectory();

    final folder = Directory(
      '${directory.path}/conversions/$ownerId',
    );
    await folder.create(recursive: true);

    // A unique folder prevents overwriting previous conversions.
    final resultFolder = await folder.createTemp('conversion_');

    final stem = fileName
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final result = File(
      '${resultFolder.path}/'
      '${stem.isEmpty ? 'document' : stem}_converted.'
      '${type.outputExtension}',
    );

    await result.writeAsBytes(output, flush: true);
    return result;
  }

  void _checkTextSize(String text) {
    if (text.trim().isEmpty) {
      throw StateError('No readable text was found.');
    }

    if (text.length > 100000) {
      throw StateError(
        'This conversion supports up to 100,000 text characters. '
        'Please split the document.',
      );
    }
  }

  Future<List<int>> _makePdf(String text) async {
    _checkTextSize(text);

    // This first version uses a built-in PDF font.
    // Reject unsupported text instead of silently losing characters.
    final normalized = text
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll('\t', '    ')
        .replaceAll('\r', '');

    if (normalized.runes.any(
      (rune) => rune != 10 && (rune < 32 || rune > 126),
    )) {
      throw StateError(
        'This PDF export currently supports English text only. '
        'Other characters require an embedded Unicode font.',
      );
    }

    final document = PdfDocument();

    try {
      final page = document.pages.add();
      final size = page.getClientSize();

      PdfTextElement(
        text: normalized,
        font: PdfStandardFont(PdfFontFamily.helvetica, 11),
      ).draw(
        page: page,
        bounds: Rect.fromLTWH(0, 0, size.width, size.height),
        format: PdfLayoutFormat(
          layoutType: PdfLayoutType.paginate,
        ),
      );

      return await document.save();
    } finally {
      document.dispose();
    }
  }

  String _escapeXml(String value) {
    return value
        .replaceAll(
          RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'),
          '',
        )
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  List<int> _makeDocx(String text) {
    final archive = Archive();

    void addXml(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addXml(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels"
    ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''',
    );

    addXml(
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1"
    Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
    Target="word/document.xml"/>
</Relationships>''',
    );

    final paragraphs = text.split('\n').map((line) {
      return '<w:p><w:r><w:t xml:space="preserve">'
          '${_escapeXml(line)}'
          '</w:t></w:r></w:p>';
    }).join();

    addXml(
      'word/document.xml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $paragraphs
    <w:sectPr/>
  </w:body>
</w:document>''',
    );

    return ZipEncoder().encode(archive);
  }

  Future<List<int>> _tablesToExcel(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final document = archive.findFile('word/document.xml');

    if (document == null || document.size > 5 * 1024 * 1024) {
      throw StateError('The DOCX is invalid or too large to process.');
    }

    final xml = XmlDocument.parse(utf8.decode(document.content));

    final tables = xml.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'tbl')
        .toList();

    if (tables.isEmpty) {
      throw StateError(
        'No Word tables were found. Paragraphs cannot be '
        'automatically mapped into spreadsheet columns.',
      );
    }

    if (tables.length > 20) {
      throw StateError('Please use a document with at most 20 tables.');
    }

    for (final table in tables) {
      final unsupported = table.descendants
          .whereType<XmlElement>()
          .any((element) => {
                'tbl',
                'gridSpan',
                'vMerge',
                'hMerge',
                'gridBefore',
                'gridAfter',
              }.contains(element.name.local));

      if (unsupported) {
        throw StateError(
          'This document contains merged or nested table cells. '
          'Use simple rectangular tables for this version.',
        );
      }
    }

    final workbook = xls.Workbook(tables.length);

    try {
      var totalCells = 0;

      for (var tableIndex = 0;
          tableIndex < tables.length;
          tableIndex++) {
        final sheet = workbook.worksheets[tableIndex];
        sheet.name = 'Table ${tableIndex + 1}';

        final rows = tables[tableIndex].childElements
            .where((element) => element.name.local == 'tr')
            .toList();

        if (rows.isEmpty) {
          throw StateError('A table has no supported rows.');
        }

        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
          final cells = rows[rowIndex].childElements
              .where((element) => element.name.local == 'tc')
              .toList();

          for (var colIndex = 0; colIndex < cells.length; colIndex++) {
            totalCells++;

            if (totalCells > 10000) {
              throw StateError(
                'This version supports at most 10,000 table cells.',
              );
            }

            final paragraphs = cells[colIndex].descendants
                .whereType<XmlElement>()
                .where((element) => element.name.local == 'p');

            final value = paragraphs.map((paragraph) {
              return paragraph.descendants
                  .whereType<XmlElement>()
                  .where((element) => element.name.local == 't')
                  .map((element) => element.innerText)
                  .join();
            }).join('\n');

            if (value.length > 32767) {
              throw StateError('A table cell contains too much text.');
            }

            // Store text explicitly, including strings beginning with "=".
            sheet
                .getRangeByIndex(rowIndex + 1, colIndex + 1)
                .setText(value);
          }
        }
      }

      return workbook.saveAsStream();
    } finally {
      workbook.dispose();
    }
  }
}