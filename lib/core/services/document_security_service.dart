import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class SecurityFinding {
  final String id;
  final String title;
  final String explanation;
  final int start;
  final int end;

  const SecurityFinding({
    required this.id,
    required this.title,
    required this.explanation,
    required this.start,
    required this.end,
  });
}

class DocumentSecurityReport {
  final String fileName;
  final String fingerprint;
  final String formatCheck;
  final String text;
  final List<String> notices;
  final List<SecurityFinding> findings;

  const DocumentSecurityReport({
    required this.fileName,
    required this.fingerprint,
    required this.formatCheck,
    required this.text,
    required this.notices,
    required this.findings,
  });
}

class DocumentSecurityService {
  static const supportedExtensions = ['pdf', 'txt', 'md', 'csv'];

  Future<DocumentSecurityReport> inspect({
    required String path,
    required String fileName,
  }) async {
    final file = File(path);

    if (!await file.exists()) {
      throw StateError('The selected file is no longer available.');
    }

    final size = await file.length();

    if (size == 0 || size > 10 * 1024 * 1024) {
      throw StateError('Select a non-empty file smaller than 10 MB.');
    }

    final extension = fileName.split('.').last.toLowerCase();

    if (!supportedExtensions.contains(extension)) {
      throw StateError('Choose a PDF, TXT, Markdown, or CSV file.');
    }

    final bytes = await file.readAsBytes();

    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw StateError('The file is empty or exceeds the 10 MB limit.');
    }

    final fingerprint = sha256.convert(bytes).toString();
    final notices = <String>[];

    String text;
    String formatCheck;

    if (extension == 'pdf') {
      // A header check is an indicator, not complete file validation.
      final header = latin1.decode(
        bytes.take(1024).toList(),
      );

      if (!header.contains('%PDF-')) {
        throw StateError(
          'The file is named PDF, but a PDF header was not found. '
          'Inspection stopped.',
        );
      }

      formatCheck = 'PDF header found; document parsed successfully.';

      PdfDocument? document;

      try {
        document = PdfDocument(inputBytes: bytes);

        if (document.pages.count > 100) {
          throw StateError(
            'This inspector supports up to 100 PDF pages per scan.',
          );
        }

        final extractor = PdfTextExtractor(document);
        final buffer = StringBuffer();
        var emptyPages = 0;

        for (var index = 0; index < document.pages.count; index++) {
          final pageText = extractor.extractText(
            startPageIndex: index,
            endPageIndex: index,
          ).trim();

          if (pageText.isEmpty) emptyPages++;

          buffer.writeln('--- Page ${index + 1} ---');
          buffer.writeln(pageText);
          buffer.writeln();

          if (buffer.length > 300000) {
            throw StateError(
              'The extracted text exceeds the 300,000-character '
              'scan limit. Select a shorter document.',
            );
          }
        }

        text = buffer.toString();

        if (emptyPages > 0) {
          notices.add(
            '$emptyPages pages have no extracted text. '
            'Images and scanned content were not inspected.',
          );
        }

        if (emptyPages == document.pages.count) {
          throw StateError(
            'No readable PDF text was found. OCR is required '
            'before text inspection.',
          );
        }
      } on StateError {
        rethrow;
      } catch (_) {
        throw StateError(
          'The PDF could not be parsed. It may be damaged, '
          'encrypted, or unsupported.',
        );
      } finally {
        document?.dispose();
      }

      notices.add(
        'PDF scripts, attachments, links stored only in annotations, '
        'and other active content are not analysed by this version.',
      );
    } else {
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        throw StateError(
          'This file is not readable UTF-8 text. '
          'Save a UTF-8 copy and try again.',
        );
      }

      if (text.contains('\u0000')) {
        throw StateError(
          'Unexpected binary or encoded content was detected. '
          'Inspection stopped.',
        );
      }

      if (text.trim().isEmpty || text.length > 300000) {
        throw StateError(
          'Select a text file containing 1–300,000 characters.',
        );
      }

      formatCheck =
          'Readable UTF-8 text. These formats have no unique magic header.';

      notices.add(
        'CSV formulas and Markdown rendering behaviour are not '
        'analysed. This is a text-pattern inspection.',
      );
    }

        return inspectText(
      text: text,
      fileName: fileName,
      fingerprint: fingerprint,
      formatCheck: formatCheck,
      notices: notices,
    );
  }

  DocumentSecurityReport inspectText({
    required String text,
    required String fileName,
    String fingerprint = '',
    String formatCheck = 'Extracted-text inspection only.',
    List<String> notices = const [],
  }) {
    if (text.length > 300000) {
      throw StateError(
        'This text section exceeds the 300,000-character review limit. '
        'Please split the document.',
      );
    }

    final reportNotices = List<String>.from(notices);

    final findings = <SecurityFinding>[];

    void addMatches(
      String title,
      String explanation,
      RegExp pattern,
    ) {
      for (final match in pattern.allMatches(text)) {
        // Stop rather than return a report that silently omits findings.
        if (findings.length >= 500) {
          throw StateError(
            'More than 500 possible findings were detected. '
            'Split this document into smaller sections.',
          );
        }

        findings.add(
          SecurityFinding(
            id: '${findings.length}',
            title: title,
            explanation: explanation,
            start: match.start,
            end: match.end,
          ),
        );
      }
    }

    addMatches(
      'Possible API key or access token',
      'A provider-style token pattern was found. '
          'This does not confirm that it is a real or active credential.',
      RegExp(
        r'\b(?:sk-or-v1-[A-Za-z0-9_-]{16,}'
        r'|sk-[A-Za-z0-9_-]{20,}'
        r'|ghp_[A-Za-z0-9]{20,}'
        r'|AIza[A-Za-z0-9_-]{30,})\b',
      ),
    );

    addMatches(
      'Possible assigned secret',
      'A password, token, or secret appears to be assigned a value.',
      RegExp(
        r'''(?:api[_ -]?key|password|access[_ -]?token|secret)\s*[:=]\s*["']?[^\s"';,]{6,}''',
        caseSensitive: false,
      ),
    );

    addMatches(
      'Email address',
      'This may be personal contact information.',
      RegExp(
        r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
        caseSensitive: false,
      ),
    );

    addMatches(
      'Possible Indian mobile number',
      'A number matches a common Indian mobile-number format. '
          'It may also be an unrelated numeric value.',
      RegExp(r'\b(?:91[- ]?)?[6-9]\d{4}[- ]?\d{5}\b'),
    );

    addMatches(
      'Possible prompt-injection instruction',
      'This text resembles an instruction directed at an AI. '
          'It may be an educational example rather than an attack.',
      RegExp(
        r'(?:ignore|disregard)\s+(?:all\s+)?'
        r'(?:previous|prior|above|system)\s+instructions'
        r'|(?:reveal|print|show)\s+(?:the\s+|your\s+)?'
        r'(?:system\s+prompt|api\s+key|password)'
        r'|you\s+are\s+now\s+(?:an?\s+)?(?:unrestricted|unfiltered)',
        caseSensitive: false,
      ),
    );

    addMatches(
      'Web link',
      'A URL appears in the extracted text. '
          'Its destination and reputation have not been checked.',
      RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false),
    );

    findings.sort((a, b) => a.start.compareTo(b.start));

   reportNotices.add(
    'Pattern matching can miss sensitive information and can flag '
    'harmless examples. No findings does not mean the file is safe.',
  );

    return DocumentSecurityReport(
      fileName: fileName,
      fingerprint: fingerprint,
      formatCheck: formatCheck,
      text: text,
      notices: List.unmodifiable(reportNotices),
      findings: List.unmodifiable(findings),
    );
  }

  String redact(
    DocumentSecurityReport report,
    Set<String> selectedIds,
  ) {
    final ranges = report.findings
        .where((finding) => selectedIds.contains(finding.id))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final output = StringBuffer();
    var cursor = 0;
    var index = 0;

    // Merge overlapping ranges so duplicate detections are safe.
    while (index < ranges.length) {
      final start = ranges[index].start;
      var end = ranges[index].end;
      index++;

      while (index < ranges.length && ranges[index].start <= end) {
        if (ranges[index].end > end) end = ranges[index].end;
        index++;
      }

      output.write(report.text.substring(cursor, start));
      output.write('[REDACTED]');
      cursor = end;
    }

    output.write(report.text.substring(cursor));
    return output.toString();
  }
}