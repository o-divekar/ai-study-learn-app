import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/services/pdf_service.dart';

class PdfRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  // Conservative text limit per document.
  static const int _maxTextBytes = 700000;

  // Keep each write batch reasonably small.
  static const int _batchSize = 10;

  /// Existing workflow. Kept for compatibility.
  Future<void> savePdfText({
    required String fileName,
    required String text,
    required String pdfPath,
    required String userId,
    String? documentId,
  }) async {
    _validateTextSize(text);

    final collection = firestore.collection('pdf_notes');

    final document = documentId == null
        ? collection.doc()
        : collection.doc(documentId);

    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(document);

      _checkOwner(existing, userId);

      transaction.set(
        document,
        {
          'fileName': fileName,
          'extractedText': text,
          'pdfPath': pdfPath,
          'userId': userId,
          if (!existing.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// New workflow: saves each page in a separate document.
  ///
  /// Generate documentId once per PDF selection and reuse it on retry.
  /// Use a new documentId when selecting a different PDF.
  ///
  /// Do not call this method concurrently for the same documentId.
  Future<void> savePdfWithPages({
    required String documentId,
    required String fileName,
    required String pdfPath,
    required String userId,
    required List<PdfPageText> pages,
  }) async {
    if (documentId.trim().isEmpty) {
      throw StateError('A PDF document ID is required.');
    }

    if (pages.isEmpty || !pages.any((page) => page.hasText)) {
      throw StateError('The PDF does not contain readable text.');
    }

    // Validate everything before starting database writes.
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];

      if (page.pageNumber != index + 1) {
        throw StateError(
          'PDF pages must be ordered and numbered starting from 1.',
        );
      }

      _validateTextSize(
        page.text,
        pageNumber: page.pageNumber,
      );
    }

    final document =
        firestore.collection('pdf_notes').doc(documentId);

    final readablePageCount =
        pages.where((page) => page.hasText).length;

    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(document);

      _checkOwner(existing, userId);

      transaction.set(
        document,
        {
          'fileName': fileName,
          'pdfPath': pdfPath,
          'userId': userId,
          'pageCount': pages.length,
          'readablePageCount': readablePageCount,
          'emptyPageCount': pages.length - readablePageCount,
          'extractionStatus': 'processing',
          'textStorage': 'pages',
          'schemaVersion': 2,

          // Page text replaces the old combined text field.
          if (existing.exists)
            'extractedText': FieldValue.delete(),

          if (!existing.exists)
            'createdAt': FieldValue.serverTimestamp(),

          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    try {
      final pageCollection = document.collection('pages');

      // Save using predictable IDs so retries overwrite the same pages.
      for (var start = 0; start < pages.length; start += _batchSize) {
        final end = start + _batchSize < pages.length
            ? start + _batchSize
            : pages.length;

        final batch = firestore.batch();

        for (var index = start; index < end; index++) {
          final page = pages[index];

          batch.set(
            pageCollection.doc(page.pageNumber.toString()),
            {
              ...page.toMap(),
              'userId': userId,
              'hasText': page.hasText,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }

        await batch.commit();
      }

      // Remove leftover page documents if this ID was reprocessed
      // with fewer pages.
      final existingPages = await pageCollection.get();

      final validIds = pages
          .map((page) => page.pageNumber.toString())
          .toSet();

      final obsoletePages = existingPages.docs
          .where((page) => !validIds.contains(page.id))
          .toList();

      for (var start = 0;
          start < obsoletePages.length;
          start += _batchSize) {
        final end = start + _batchSize < obsoletePages.length
            ? start + _batchSize
            : obsoletePages.length;

        final batch = firestore.batch();

        for (var index = start; index < end; index++) {
          batch.delete(obsoletePages[index].reference);
        }

        await batch.commit();
      }

      // Only mark ready after every page has been saved.
      await document.update({
        'extractionStatus': 'ready',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Preserve the original error if this status update also fails.
      try {
        await document.update({
          'extractionStatus': 'failed',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      rethrow;
    }
  }

  void _checkOwner(
    DocumentSnapshot<Map<String, dynamic>> existing,
    String userId,
  ) {
    if (existing.exists && existing.data()?['userId'] != userId) {
      throw StateError('This PDF belongs to another account.');
    }
  }

  void _validateTextSize(
    String text, {
    int? pageNumber,
  }) {
    if (utf8.encode(text).length > _maxTextBytes) {
      throw StateError(
        pageNumber == null
            ? 'The extracted text is too large for one document. '
                'Use page-based storage.'
            : 'Page $pageNumber contains too much text for one '
                'page record. It needs to be split into smaller passages.',
      );
    }
  }
}