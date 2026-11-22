import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note_model.dart';

class NotesRepository {
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  Future<void> createNote(NoteModel note) async {
    await _firestore
        .collection('notes')
        .doc(note.id)
        .set(note.toMap());
  }
  Future<void> updateNote(NoteModel note) async {
    await _firestore
      .collection('notes')
      .doc(note.id)
      .update(note.toMap());
  }

  Future<void> deleteNote(String noteId) async {
    await _firestore
      .collection('notes')
      .doc(noteId)
      .delete();
  }

  Stream<List<NoteModel>> getNotes(String userId) {
    return _firestore
        .collection('notes')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return NoteModel.fromMap(doc.data());
      }).toList();
    });
  }
}