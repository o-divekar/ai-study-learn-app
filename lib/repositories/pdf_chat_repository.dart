import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/services/openrouter_service.dart';

class PdfChatEntry {
  final String id;
  final String question;
  final PdfAnswer answer;

  const PdfChatEntry({
    required this.id,
    required this.question,
    required this.answer,
  });
}

class PdfChatRepository {
  CollectionReference<Map<String, dynamic>> _collection(String pdfId) {
    return FirebaseFirestore.instance
        .collection('pdf_notes')
        .doc(pdfId)
        .collection('chat_history');
  }

  String createId(String pdfId) => _collection(pdfId).doc().id;

  Future<void> save({
    required String pdfId,
    required String ownerId,
    required String messageId,
    required String question,
    required PdfAnswer answer,
  }) async {
    // Reusing messageId makes a save retry overwrite the same entry.
    await _collection(pdfId).doc(messageId).set({
      'userId': ownerId,
      'question': question,
      'answer': answer.answer,
      'found': answer.foundInProvidedPassages,
      'sources': answer.sources.map((source) => {
        'passageId': source.passageId,
        'pageNumber': source.pageNumber,
        'quote': source.quote,
      }).toList(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<PdfChatEntry>> load(String pdfId) async {
    final snapshot = await _collection(pdfId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get(const GetOptions(source: Source.server));

    final entries = <PdfChatEntry>[];

    for (final document in snapshot.docs) {
      final data = document.data();
      final question = data['question'];
      final answer = data['answer'];
      final found = data['found'];
      final rawSources = data['sources'];

      if (question is! String ||
          answer is! String ||
          found is! bool ||
          rawSources is! List) {
        throw StateError('A saved conversation entry is invalid.');
      }

      final sources = <PdfAnswerSource>[];

      for (final item in rawSources) {
        if (item is! Map ||
            item['passageId'] is! String ||
            item['pageNumber'] is! int ||
            item['quote'] is! String) {
          throw StateError('A saved source reference is invalid.');
        }

        sources.add(
          PdfAnswerSource(
            passageId: item['passageId'] as String,
            pageNumber: item['pageNumber'] as int,
            quote: item['quote'] as String,
          ),
        );
      }

      entries.add(
        PdfChatEntry(
          id: document.id,
          question: question,
          answer: PdfAnswer(
            answer: answer,
            foundInProvidedPassages: found,
            sources: List.unmodifiable(sources),
          ),
        ),
      );
    }

    // Display the most recent 50 entries in chronological order.
    return entries.reversed.toList();
  }
}