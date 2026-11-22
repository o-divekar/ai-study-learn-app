import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Text extracted from one physical PDF page.
/// Page numbers start at 1, matching the viewer's page position.
class PdfPageText {
  final int pageNumber;
  final String text;

  const PdfPageText({
    required this.pageNumber,
    required this.text,
  });

  bool get hasText => text.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'pageNumber': pageNumber,
      'text': text,
    };
  }
}

class PdfService {
  /// Preserves compatibility with the existing upload workflow.
  Future<String> extractText(String path) async {
    final pages = await extractPages(path);

    return pages
        .where((page) => page.hasText)
        .map((page) => page.text)
        .join('\n\n');
  }

  /// Extracts every page separately for retrieval and citations.
  ///
  /// Empty pages are retained so page numbering stays accurate.
  /// Throws an error if the entire document has no readable text.
  Future<List<PdfPageText>> extractPages(String path) async {
    if (path.trim().isEmpty) {
      throw StateError(
        'No PDF path was provided. Please select the file again.',
      );
    }

    PdfDocument? document;

    try {
      final file = File(path);

      if (!await file.exists()) {
        throw StateError(
          'The PDF file could not be found. '
          'Please select it again.',
        );
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw StateError(
          'The selected file is empty. Please choose another PDF.',
        );
      }

      document = PdfDocument(inputBytes: bytes);

      final pageCount = document.pages.count;

      if (pageCount == 0) {
        throw StateError('The PDF does not contain any pages.');
      }

      final extractor = PdfTextExtractor(document);
      final pages = <PdfPageText>[];

      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final extractedText = extractor.extractText(
          startPageIndex: pageIndex,
          endPageIndex: pageIndex,
        );

        pages.add(
          PdfPageText(
            pageNumber: pageIndex + 1,
            text: _normalizeText(extractedText),
          ),
        );
      }

      if (!pages.any((page) => page.hasText)) {
        throw StateError(
          'No readable text was found in this PDF. '
          'It may contain scanned images and require OCR.',
        );
      }

      return List<PdfPageText>.unmodifiable(pages);
    } on FileSystemException {
      throw StateError(
        'The PDF could not be read from this device. '
        'Please select the file again.',
      );
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'Text extraction failed. The PDF may be damaged, '
        'password-protected, or unsupported. '
        'Try opening it in a PDF reader or select another copy.',
      );
    } finally {
      document?.dispose();
    }
  }

  String _normalizeText(String text) {
    // Preserve line breaks and paragraph structure.
    return text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u0000', '')
        .trim();
  }
}