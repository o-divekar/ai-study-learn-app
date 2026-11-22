import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'flashcard_screen.dart';
import 'quiz_screen.dart';

class SavedActivitiesScreen extends StatefulWidget {
  const SavedActivitiesScreen({super.key});

  @override
  State<SavedActivitiesScreen> createState() =>
      _SavedActivitiesScreenState();
}

class _SavedActivitiesScreenState extends State<SavedActivitiesScreen> {
  String? _userId;

  Stream<QuerySnapshot<Map<String, dynamic>>>? _quizzes;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _flashcards;

  @override
  void initState() {
    super.initState();

    _userId = FirebaseAuth.instance.currentUser?.uid;

    if (_userId != null) {
      _quizzes = FirebaseFirestore.instance
          .collection('quizzes')
          .where('userId', isEqualTo: _userId)
          .snapshots();

      _flashcards = FirebaseFirestore.instance
          .collection('flashcards')
          .where('userId', isEqualTo: _userId)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Saved Study Activities'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.quiz_outlined),
                text: 'Quizzes',
              ),
              Tab(
                icon: Icon(Icons.style_outlined),
                text: 'Flashcards',
              ),
            ],
          ),
        ),
        body: _userId == null
            ? const Center(child: Text('Please log in first.'))
            : TabBarView(
                children: [
                  _buildList(isQuiz: true, stream: _quizzes!),
                  _buildList(isQuiz: false, stream: _flashcards!),
                ],
              ),
      ),
    );
  }

  Widget _buildList({
    required bool isQuiz,
    required Stream<QuerySnapshot<Map<String, dynamic>>> stream,
  }) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Could not load saved activities. '
                'Check your connection and Firestore permissions.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final documents = snapshot.data!.docs;

        if (documents.isEmpty) {
          return Center(
            child: Text(
              isQuiz
                  ? 'No saved quizzes yet.'
                  : 'No saved flashcard sets yet.',
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: documents.length,
          itemBuilder: (context, index) {
            final data = documents[index].data();
            final field = isQuiz ? 'quiz' : 'flashcards';

            final content = data[field];
            final fileName = data['fileName'];

            final valid = content is String && content.trim().isNotEmpty;

            return Card(
              child: ListTile(
                leading: Icon(
                  isQuiz ? Icons.quiz_rounded : Icons.style_rounded,
                  color: const Color(0xFF6750E8),
                ),
                title: Text(
                  fileName is String ? fileName : 'Study activity',
                ),
                subtitle: Text(
                  valid
                      ? 'Tap to open'
                      : 'This record has no readable content.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: !valid
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => isQuiz
                                ? QuizScreen(quiz: content as String)
                                : FlashcardScreen(
                                    flashcards: content as String,
                                  ),
                          ),
                        );
                      },
              ),
            );
          },
        );
      },
    );
  }
}