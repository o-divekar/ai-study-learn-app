import 'package:ai_study_notes/repositories/summary_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/openrouter_service.dart';

class TestAiScreen extends StatefulWidget {
  const TestAiScreen({super.key});

  @override
  State<TestAiScreen> createState() => _TestAiScreenState();
}

class _TestAiScreenState extends State<TestAiScreen> {
  final _formKey = GlobalKey<FormState>();

  final _textController = TextEditingController(
    text: 'Flutter is an open-source UI toolkit developed by Google.\n'
        'Firebase provides backend services.\n'
        'Riverpod is a state management library.',
  );

  final _aiService = OpenRouterService();
  final _summaryRepository = SummaryRepository();

  String summary = '';
  String? _documentId;
  String? _ownerId;
  String? _error;

  bool _isGenerating = false;
  bool _isSaving = false;
  bool _isSaved = false;

  bool get _isBusy => _isGenerating || _isSaving;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool _sameVerifiedUser(String uid) {
    final user = FirebaseAuth.instance.currentUser;

    return user != null &&
        user.uid == uid &&
        user.emailVerified;
  }

  Future<void> generateSummary() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || !user.emailVerified) {
      setState(() {
        _error = 'Please log in with a verified email first.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    final input = _textController.text.trim();

    setState(() {
      _isGenerating = true;
      _error = null;
    });

    try {
      final result = await _aiService.generateSummary(input);

      if (!mounted) return;

      if (!_sameVerifiedUser(user.uid)) {
        throw StateError(
          'Your session changed. Please log in again.',
        );
      }

      if (result.trim().isEmpty) {
        throw StateError('The AI returned an empty summary.');
      }

      setState(() {
        summary = result;
        _ownerId = user.uid;
        _documentId = FirebaseFirestore.instance
            .collection('summaries')
            .doc()
            .id;
        _isSaved = false;
      });

      await _saveSummary();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e is StateError
            ? e.message.toString()
            : 'Could not generate the summary. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _saveSummary() async {
    if (_isSaving ||
        _isSaved ||
        summary.isEmpty ||
        _ownerId == null ||
        _documentId == null) {
      return;
    }

    if (!_sameVerifiedUser(_ownerId!)) {
      if (!mounted) return;

      setState(() {
        _error = 'Please log in again before saving this summary.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await _summaryRepository.saveSummary(
        documentId: _documentId!,
        userId: _ownerId!,
        fileName: 'AI Playground — Text Summary',
        summary: summary,
      );

      if (!mounted) return;

      setState(() {
        _isSaved = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e is FirebaseException &&
                e.code == 'permission-denied'
            ? 'The summary was generated, but saving was denied. '
                'Check your Firestore rules and email verification.'
            : 'The summary was generated but could not be saved. '
                'Check your connection and tap Retry Saving.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);

    final secondaryColor =
        isDark ? Colors.white70 : const Color(0xFF74788D);

    final cardColor =
        isDark ? const Color(0xFF1C1C2C) : Colors.white;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'AI Playground',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 750),
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                        SizedBox(height: 18),
                        Text(
                          'Try an AI summary',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Paste a short passage and turn it into '
                          'clear study points.',
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Study material',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: _textController,
                            enabled: !_isBusy,
                            minLines: 5,
                            maxLines: 12,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            decoration: InputDecoration(
                              hintText: 'Paste your study text here...',
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF252536)
                                  : const Color(0xFFF7F8FC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: _primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter some study material';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _isBusy ? null : generateSummary,
                            icon: _isBusy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome_rounded),
                            label: Text(
                              _isSaving
                                  ? 'Saving summary...'
                                  : _isGenerating
                                      ? 'Generating summary...'
                                      : 'Generate Summary',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Text(
                      'Generated summary',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: SelectableText(
                        summary,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          height: 1.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_isSaved)
                      const Text(
                        'Saved to AI Summaries.',
                        style: TextStyle(
                          color: Color(0xFF209C86),
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else if (!_isBusy)
                      OutlinedButton.icon(
                        onPressed: _saveSummary,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Retry Saving'),
                      ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Each successful generation creates a new saved '
                    'summary. Check the result against your source text.',
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