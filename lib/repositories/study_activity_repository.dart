import 'package:cloud_firestore/cloud_firestore.dart';

class StudyActivityRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String createId() {
    return _firestore.collection('quizzes').doc().id;
  }

  Future<void> saveQuiz({
    required String id,
    required String userId,
    required String fileName,
    required String quiz,
  }) {
    return _save(
      collection: 'quizzes',
      id: id,
      userId: userId,
      data: {
        'fileName': fileName,
        'quiz': quiz,
      },
    );
  }

  Future<void> saveFlashcards({
    required String id,
    required String userId,
    required String fileName,
    required String flashcards,
  }) {
    return _save(
      collection: 'flashcards',
      id: id,
      userId: userId,
      data: {
        'fileName': fileName,
        'flashcards': flashcards,
      },
    );
  }

  Future<void> _save({
    required String collection,
    required String id,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    final reference = _firestore.collection(collection).doc(id);

    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);

      if (existing.exists &&
          existing.data()?['userId'] != userId) {
        throw StateError('This activity belongs to another user.');
      }

      transaction.set(
        reference,
        {
          ...data,
          'userId': userId,
          if (!existing.exists)
            'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
} 