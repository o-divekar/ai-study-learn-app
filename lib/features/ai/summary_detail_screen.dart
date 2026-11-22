import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/openrouter_service.dart';
import '../../repositories/study_activity_repository.dart';
import 'flashcard_screen.dart';
import 'quiz_screen.dart';
import 'summary_source_screen.dart';

class SummaryDetailScreen extends StatefulWidget {
  final String fileName;
  final String summary;

  // Optional so existing navigation still compiles.
  final String? summaryId;
  final String? ownerId;

  const SummaryDetailScreen({
    super.key,
    required this.fileName,
    required this.summary,
    this.summaryId,
    this.ownerId,
  });

  @override
  State<SummaryDetailScreen> createState() =>
      _SummaryDetailScreenState();
}

class _SummaryDetailScreenState extends State<SummaryDetailScreen> {
  final _aiService = OpenRouterService();
  final _activityRepository = StudyActivityRepository();

  String? _screenOwnerId;

  String? _generatedQuiz;
  String? _generatedFlashcards;
  String? _quizId;
  String? _flashcardsId;

  bool _quizSaved = false;
  bool _flashcardsSaved = false;
  bool _isGeneratingQuiz = false;
  bool _isGeneratingFlashcards = false;

  int _revision = 0;

  static const _primaryColor = Color(0xFF6750E8);

  bool get _isBusy => _isGeneratingQuiz || _isGeneratingFlashcards;
  bool get _hasSummary => widget.summary.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _screenOwnerId =
        widget.ownerId ?? FirebaseAuth.instance.currentUser?.uid;
  }

  void _resetActivities() {
    _generatedQuiz = null;
    _generatedFlashcards = null;
    _quizId = null;
    _flashcardsId = null;
    _quizSaved = false;
    _flashcardsSaved = false;
  }

  @override
  void didUpdateWidget(covariant SummaryDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.summary != widget.summary ||
        oldWidget.fileName != widget.fileName ||
        oldWidget.summaryId != widget.summaryId ||
        oldWidget.ownerId != widget.ownerId) {
      _revision++;
      _resetActivities();
      _screenOwnerId =
          widget.ownerId ?? FirebaseAuth.instance.currentUser?.uid;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _sessionValid() {
    final user = FirebaseAuth.instance.currentUser;

    return user != null &&
        user.emailVerified &&
        user.uid == _screenOwnerId;
  }

  Future<void> _copySummary() async {
    if (!_sessionValid()) {
      _showMessage('Please sign in with the account that owns this summary.');
      return;
    }

    try {
      await Clipboard.setData(
        ClipboardData(text: widget.summary),
      );
      _showMessage('Summary copied.');
    } catch (_) {
      _showMessage('Could not copy the summary.');
    }
  }

  void _viewSource() {
    if (!_sessionValid()) {
      _showMessage('Please sign in with your verified account.');
      return;
    }

    final id = widget.summaryId;

    if (id == null || id.trim().isEmpty) {
      _showMessage(
        'Source unavailable. Open this summary from AI Summaries '
        'to load its saved record.',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SummarySourceScreen(
          summaryId: id,
          fileName: widget.fileName,
          ownerId: _screenOwnerId!,
        ),
      ),
    );
  }

  Future<void> _generateActivity({required bool quiz}) async {
    if (_isBusy || !_hasSummary) return;

    if (!_sessionValid()) {
      _showMessage(
        'Please sign in with the verified account '
        'that owns this summary.',
      );
      return;
    }

    final ownerId = _screenOwnerId!;
    final sourceSummary = widget.summary;
    final sourceFileName = widget.fileName;
    final revision = _revision;

    bool stillCurrent() =>
        mounted && revision == _revision && _sessionValid();

    setState(() {
      if (quiz) {
        _isGeneratingQuiz = true;
      } else {
        _isGeneratingFlashcards = true;
      }
    });

    try {
      final String result;

      if (quiz) {
        result = _generatedQuiz ??
            await _aiService.generateQuiz(sourceSummary);
      } else {
        result = _generatedFlashcards ??
            await _aiService.generateFlashcards(sourceSummary);
      }

      if (!stillCurrent()) return;

      if (result.trim().isEmpty) {
        throw StateError('The AI returned an empty activity.');
      }

      if (quiz) {
        _generatedQuiz = result;
        _quizId ??= _activityRepository.createId();

        if (!_quizSaved) {
          await _activityRepository.saveQuiz(
            id: _quizId!,
            userId: ownerId,
            fileName: sourceFileName,
            quiz: result,
          );

          if (!stillCurrent()) return;
          _quizSaved = true;
        }
      } else {
        _generatedFlashcards = result;
        _flashcardsId ??= _activityRepository.createId();

        if (!_flashcardsSaved) {
          await _activityRepository.saveFlashcards(
            id: _flashcardsId!,
            userId: ownerId,
            fileName: sourceFileName,
            flashcards: result,
          );

          if (!stillCurrent()) return;
          _flashcardsSaved = true;
        }
      }

      if (!stillCurrent()) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => quiz
              ? QuizScreen(quiz: result)
              : FlashcardScreen(flashcards: result),
        ),
      );
    } catch (error) {
      if (!stillCurrent()) return;

      final pendingSave = quiz
          ? _generatedQuiz != null && !_quizSaved
          : _generatedFlashcards != null && !_flashcardsSaved;

      _showMessage(
        pendingSave
            ? 'Activity generated, but saving failed. '
                'Check your connection and permissions, then retry saving.'
            : error is StateError
                ? error.message.toString()
                : 'Generation could not finish. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingQuiz = false;
          _isGeneratingFlashcards = false;
        });
      }
    }
  }

  Widget _spinner() {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  String _activityLabel({required bool quiz}) {
    final generating =
        quiz ? _isGeneratingQuiz : _isGeneratingFlashcards;
    final generated =
        quiz ? _generatedQuiz != null : _generatedFlashcards != null;
    final saved = quiz ? _quizSaved : _flashcardsSaved;
    final name = quiz ? 'Quiz' : 'Flashcards';

    if (generating) return 'Preparing $name...';
    if (generated && !saved) return 'Retry Saving $name';
    if (saved) return 'Open $name';
    return 'Generate $name';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);
    final secondaryColor =
        isDark ? const Color(0xFFB3B5C9) : const Color(0xFF74788D);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Copy summary',
            onPressed: _hasSummary ? _copySummary : null,
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF8070EF),
                          Color(0xFF5540C9),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Your study summary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _viewSource,
                    icon: const Icon(Icons.find_in_page_outlined),
                    label: const Text('View source text'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Compare the summary with saved source text '
                    'to check for missing or unsupported information.',
                    style: TextStyle(
                      color: secondaryColor,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C2C)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _hasSummary
                        ? SelectableText(
                            widget.summary,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              height: 1.8,
                            ),
                          )
                        : const Column(
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 42,
                              ),
                              SizedBox(height: 14),
                              Text('No summary available'),
                              SizedBox(height: 10),
                              Text(
                                'Go back and generate a summary first.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Turn understanding into practice',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Test yourself with a quiz or revise using '
                    'question-and-answer flashcards.',
                    style: TextStyle(
                      color: secondaryColor,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _isBusy || !_hasSummary
                        ? null
                        : () => _generateActivity(quiz: true),
                    icon: _isGeneratingQuiz
                        ? _spinner()
                        : const Icon(Icons.quiz_rounded),
                    label: Text(_activityLabel(quiz: true)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isBusy || !_hasSummary
                        ? null
                        : () => _generateActivity(quiz: false),
                    icon: _isGeneratingFlashcards
                        ? _spinner()
                        : const Icon(Icons.style_rounded),
                    label: Text(_activityLabel(quiz: false)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryColor,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  if (!_isBusy &&
                      (_generatedQuiz != null ||
                          _generatedFlashcards != null)) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        setState(_resetActivities);
                        _showMessage(
                          'Ready to generate new activities. '
                          'Previously saved activities remain available.',
                        );
                      },
                      child: const Text('Start fresh generation'),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    _isBusy
                        ? 'Keep this screen open while your activity '
                            'is generated and saved.'
                        : 'Check AI-generated content against '
                            'your study material.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: secondaryColor,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}