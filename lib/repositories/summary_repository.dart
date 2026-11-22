import 'package:cloud_firestore/cloud_firestore.dart';

class SummaryRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> saveSummary({
    required String userId,
    required String fileName,
    required String summary,
    String? documentId,
    String? pdfId,
  }) async {
    final collection = firestore.collection('summaries');

    final document = documentId == null
        ? collection.doc()
        : collection.doc(documentId);

    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(document);

      if (existing.exists && existing.data()?['userId'] != userId) {
        throw StateError('This summary belongs to another account.');
      }

      transaction.set(
        document,
        {
          'userId': userId,
          'fileName': fileName,
          'summary': summary,
          if (pdfId != null) 'pdfId': pdfId,
          if (!existing.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}