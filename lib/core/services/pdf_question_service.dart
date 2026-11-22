import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'openrouter_service.dart';

class PdfQuestionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OpenRouterService _ai = OpenRouterService();

  void _checkUser(String ownerId) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null ||
        user.uid != ownerId ||
        !user.emailVerified) {
      throw StateError(
        'Please sign in with your verified account again.',
      );
    }
  }

  Future<PdfAnswer> ask({
    required String pdfId,
    required String ownerId,
    required String question,
  }) async {
    _checkUser(ownerId);

    final cleanQuestion = question.trim();

    if (cleanQuestion.isEmpty || cleanQuestion.length > 1000) {
      throw StateError(
        'Enter a question between 1 and 1,000 characters.',
      );
    }

    final reference = _firestore.collection('pdf_notes').doc(pdfId);

    final snapshot = await reference.get(
      const GetOptions(source: Source.server),
    );

    _checkUser(ownerId);

    final data = snapshot.data();

    if (!snapshot.exists || data == null) {
      throw StateError('This PDF record no longer exists.');
    }

    if (data['userId'] != ownerId) {
      throw StateError('This PDF belongs to another account.');
    }

    if (data['extractionStatus'] != 'ready' ||
        data['textStorage'] != 'pages') {
      throw StateError(
        'This PDF is not ready for questions. '
        'Finish processing it, or upload it again using '
        'the updated upload screen.',
      );
    }

    final pageCount = data['pageCount'];

    // A bounded first version for chapter-sized documents.
    if (pageCount is! int || pageCount < 1 || pageCount > 200) {
      throw StateError(
        'This version supports PDFs with 1–200 pages. '
        'For larger documents, upload a chapter separately.',
      );
    }

    final pageSnapshot = await reference
        .collection('pages')
        .limit(201)
        .get(const GetOptions(source: Source.server));

    _checkUser(ownerId);

    if (pageSnapshot.docs.length != pageCount) {
      throw StateError(
        'Some PDF pages are missing or incomplete. '
        'Please upload the document again.',
      );
    }

    final pages = <int, String>{};
    var totalBytes = 0;

    for (final document in pageSnapshot.docs) {
      final page = document.data();
      final number = page['pageNumber'];
      final text = page['text'];

      if (number is! int ||
          number < 1 ||
          number > pageCount ||
          text is! String ||
          page['userId'] != ownerId ||
          pages.containsKey(number)) {
        throw StateError(
          'The saved page data is invalid. Please upload the PDF again.',
        );
      }

      totalBytes += utf8.encode(text).length;

      if (totalBytes > 2000000) {
        throw StateError(
          'This PDF contains too much text for this version of '
          'Ask PDF. Please upload a shorter chapter.',
        );
      }

      pages[number] = text;
    }

    final passages = <PdfPassage>[];

    // Process pages numerically: document IDs sort as 1, 10, 11, 2...
    for (var pageNumber = 1; pageNumber <= pageCount; pageNumber++) {
      final text = pages[pageNumber]!;

      final words = text
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();

      // 180-word passages with 40-word overlap.
      for (var start = 0; start < words.length; start += 140) {
        final end = math.min(start + 180, words.length);

        passages.add(
          PdfPassage(
            id: 'p${pageNumber}_$start',
            pageNumber: pageNumber,
            text: words.sublist(start, end).join(' '),
          ),
        );

        if (end == words.length) break;
      }
    }

    if (passages.isEmpty) {
      throw StateError(
        'This PDF has no readable text. Scanned pages require OCR.',
      );
    }

    final relevant = _retrieve(cleanQuestion, passages);

    _checkUser(ownerId);

    final result = await _ai.answerPdfQuestion(
      question: cleanQuestion,
      passages: relevant,
    );

    _checkUser(ownerId);

    return result;
  }

  Set<String> _terms(String text) {
    const stopWords = {
      'a', 'an', 'the', 'is', 'are', 'was', 'were',
      'be', 'been', 'being', 'of', 'in', 'on', 'at',
      'to', 'for', 'from', 'by', 'and', 'or', 'with',
      'this', 'that', 'these', 'those', 'it', 'its',
      'what', 'which', 'who', 'when', 'where', 'how',
      'why', 'do', 'does', 'did', 'can', 'could',
      'would', 'should', 'please', 'explain', 'describe',
      'define', 'tell', 'me', 'about', 'pdf', 'document',
    };

    return RegExp(r'[\p{L}\p{N}]+', unicode: true)
        .allMatches(text.toLowerCase())
        .map((match) => match.group(0)!)
        .where((term) => !stopWords.contains(term))
        .toSet();
  }

  List<PdfPassage> _retrieve(
    String question,
    List<PdfPassage> passages,
  ) {
    final queryTerms = _terms(question);

    if (queryTerms.isEmpty) {
      throw StateError(
        'Include a specific topic in your question, '
        'for example: "What is gradient descent?"',
      );
    }

    final passageTerms = passages
        .map((passage) => _terms(passage.text))
        .toList();

    // Give more weight to terms that occur in fewer passages.
    final weights = <String, double>{};

    for (final term in queryTerms) {
      final frequency = passageTerms
          .where((terms) => terms.contains(term))
          .length;

      weights[term] =
          1 + math.log((passages.length + 1) / (frequency + 1));
    }

    final scores = <int, double>{};

    for (var index = 0; index < passages.length; index++) {
      var score = 0.0;

      for (final term in queryTerms) {
        if (passageTerms[index].contains(term)) {
          score += weights[term]!;
        }
      }

      if (score > 0) scores[index] = score;
    }

    final ranked = scores.keys.toList()
      ..sort((a, b) {
        final comparison = scores[b]!.compareTo(scores[a]!);
        return comparison != 0 ? comparison : a.compareTo(b);
      });

    final selected = <PdfPassage>[];

    for (final index in ranked) {
      if (selected.length == 6) break;

      final candidate = [...selected, passages[index]];

      final payload = jsonEncode({
        'question': question,
        'passages': candidate.map((item) => item.toJson()).toList(),
      });

      // Matches the answerPdfQuestion request-size safeguard.
      if (utf8.encode(payload).length <= 40000) {
        selected.add(passages[index]);
      }
    }

    if (ranked.isNotEmpty && selected.isEmpty) {
      throw StateError(
        'The matching passages are too large. '
        'Try a shorter document.',
      );
    }

    return selected;
  }
}