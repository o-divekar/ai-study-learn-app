import 'dart:convert';

import 'package:flutter/material.dart';

class FlashcardScreen extends StatefulWidget {
  final String flashcards;

  const FlashcardScreen({
    super.key,
    required this.flashcards,
  });

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  List<Map<String, String>> _cards = [];

  int _index = 0;
  bool _showAnswer = false;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();
    _parseCards();
  }

  @override
  void didUpdateWidget(covariant FlashcardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.flashcards != widget.flashcards) {
      _parseCards();
    }
  }

  void _parseCards() {
    _cards = [];
    _index = 0;
    _showAnswer = false;

    try {
      final decoded = jsonDecode(widget.flashcards);

      if (decoded is! List || decoded.isEmpty) return;

      final parsed = <Map<String, String>>[];

      for (final item in decoded) {
        if (item is! Map ||
            item['question'] is! String ||
            item['answer'] is! String) {
          return;
        }

        final question = (item['question'] as String).trim();
        final answer = (item['answer'] as String).trim();

        if (question.isEmpty || answer.isEmpty) return;

        parsed.add({
          'question': question,
          'answer': answer,
        });
      }

      _cards = parsed;
    } on FormatException {
      // Older plain-text flashcards use the fallback view.
    }
  }

  void _move(int direction) {
    final next = _index + direction;

    if (next < 0 || next >= _cards.length) return;

    setState(() {
      _index = next;
      _showAnswer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);

    final secondaryColor =
        isDark ? Colors.white70 : const Color(0xFF74788D);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'Flashcards',
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
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: _cards.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.style_outlined,
                          size: 48,
                          color: _primaryColor,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.flashcards.trim().isEmpty
                              ? 'No flashcards to display'
                              : 'Saved revision material',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.flashcards.trim().isNotEmpty) ...[
                          Text(
                            'This content is not in the interactive '
                            'card format. Generate a new set to use '
                            'question-and-answer cards.',
                            style: TextStyle(
                              color: secondaryColor,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SelectableText(
                            widget.flashcards,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              height: 1.7,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Recall. Reveal. Repeat.',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Try answering before revealing the explanation.',
                          style: TextStyle(
                            color: secondaryColor,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'Card ${_index + 1} of ${_cards.length}',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: (_index + 1) / _cards.length,
                          color: _primaryColor,
                          backgroundColor: _primaryColor.withAlpha(25),
                        ),
                        const SizedBox(height: 24),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          constraints: const BoxConstraints(
                            minHeight: 280,
                          ),
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: _showAnswer
                                ? (isDark
                                    ? const Color(0xFF202C2B)
                                    : const Color(0xFFF0FAF6))
                                : (isDark
                                    ? const Color(0xFF1C1C2C)
                                    : Colors.white),
                            borderRadius: BorderRadius.circular(26),
                            border: Border.all(
                              color: _showAnswer
                                  ? const Color(0xFF209C86)
                                  : _primaryColor.withAlpha(65),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _showAnswer ? 'ANSWER' : 'QUESTION',
                                style: TextStyle(
                                  color: _showAnswer
                                      ? const Color(0xFF209C86)
                                      : _primaryColor,
                                  fontSize: 12,
                                  letterSpacing: 2,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SelectableText(
                                _cards[_index][
                                    _showAnswer ? 'answer' : 'question']!,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 21,
                                  height: 1.6,
                                  fontWeight: _showAnswer
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _showAnswer = !_showAnswer;
                            });
                          },
                          icon: const Icon(Icons.flip_rounded),
                          label: Text(
                            _showAnswer ? 'Show Question' : 'Show Answer',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primaryColor,
                            minimumSize: const Size.fromHeight(52),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  _index == 0 ? null : () => _move(-1),
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Previous'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _index == _cards.length - 1
                                  ? null
                                  : () => _move(1),
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Next'),
                            ),
                          ],
                        ),
                        if (_index == _cards.length - 1) ...[
                          const SizedBox(height: 18),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _index = 0;
                                _showAnswer = false;
                              });
                            },
                            icon: const Icon(Icons.replay_rounded),
                            label: const Text('Review Again'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}