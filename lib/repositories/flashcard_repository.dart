import 'package:cloud_firestore/cloud_firestore.dart';

class FlashcardRepository {

  final FirebaseFirestore firestore =
      FirebaseFirestore.instance;

  Future<void> saveFlashcards({
    required String userId,
    required String fileName,
    required String flashcards,
  }) async {

    await firestore
        .collection('flashcards')
        .add({

      'userId': userId,
      'fileName': fileName,
      'flashcards': flashcards,
      'createdAt': Timestamp.now(),

    });
  }
}