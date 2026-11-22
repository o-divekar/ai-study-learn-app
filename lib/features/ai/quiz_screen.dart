import 'package:flutter/material.dart';

class QuizScreen extends StatefulWidget {
  final String quiz;

  const QuizScreen({
    super.key,
    required this.quiz,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  static const _primary = Color(0xFF6750E8);
  static const _green = Color(0xFF209C86);
  static const _red = Color(0xFFD95468);

  List<_QuizQuestion> _questions = [];
  List<int?> _answers = [];

  int _currentIndex = 0;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  @override
  void didUpdateWidget(covariant QuizScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.quiz != widget.quiz) {
      _loadQuiz();
    }
  }

  void _loadQuiz() {
    _questions = _parseQuiz(widget.quiz);
    _answers = List<int?>.filled(_questions.length, null);
    _currentIndex = 0;
    _submitted = false;
  }

  List<_QuizQuestion> _parseQuiz(String input) {
    // Remove common markdown emphasis used by AI responses.
    final text = input
        .replaceAll('\r\n', '\n')
        .replaceAll('**', '')
        .replaceAll('__', '');

    final questionMarker = RegExp(
      r'^\s*(?:\d+[.)]\s*)?Question(?:\s+\d+)?\s*:',
      multiLine: true,
      caseSensitive: false,
    );

    final markers = questionMarker.allMatches(text).toList();

    if (markers.isEmpty) return [];

    final parsed = <_QuizQuestion>[];

    for (var i = 0; i < markers.length; i++) {
      final start = markers[i].end;
      final end =
          i + 1 < markers.length ? markers[i + 1].start : text.length;

      final block = text.substring(start, end).trim();

      final answerMatches = RegExp(
        r'^\s*(?:Correct\s+)?Answer\s*:\s*'
        r'\(?([A-D])\)?(?=\s|[.):,\-]|$)',
        multiLine: true,
        caseSensitive: false,
      ).allMatches(block).toList();

      if (answerMatches.length != 1) return [];

      final answerMatch = answerMatches.single;
      final questionAndOptions = block.substring(0, answerMatch.start);

      final options = RegExp(
        r'^\s*([A-D])[.)]\s*',
        multiLine: true,
        caseSensitive: false,
      ).allMatches(questionAndOptions).toList();

      if (options.length != 4) return [];

      final question =
          questionAndOptions.substring(0, options.first.start).trim();

      if (question.isEmpty) return [];

      final optionTexts = <String>[];

      for (var j = 0; j < 4; j++) {
        final expectedLabel = String.fromCharCode(65 + j);

        if (options[j].group(1)!.toUpperCase() != expectedLabel) {
          return [];
        }

        final optionEnd = j + 1 < options.length
            ? options[j + 1].start
            : questionAndOptions.length;

        final optionText = questionAndOptions
            .substring(options[j].end, optionEnd)
            .trim();

        if (optionText.isEmpty) return [];

        optionTexts.add(optionText);
      }

      final correctIndex =
          answerMatch.group(1)!.toUpperCase().codeUnitAt(0) - 65;

      parsed.add(
        _QuizQuestion(
          question: question,
          options: optionTexts,
          correctIndex: correctIndex,
        ),
      );
    }

    return parsed;
  }

  int get _answeredCount =>
      _answers.where((answer) => answer != null).length;

  int get _score {
    var score = 0;

    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] == _questions[i].correctIndex) {
        score++;
      }
    }

    return score;
  }

  void _submit() {
    final firstUnanswered = _answers.indexWhere((answer) => answer == null);

    if (firstUnanswered != -1) {
      setState(() {
        _currentIndex = firstUnanswered;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please answer every question before submitting.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _submitted = true;
      _currentIndex = 0;
    });
  }

  void _retry() {
    setState(() {
      _answers = List<int?>.filled(_questions.length, null);
      _currentIndex = 0;
      _submitted = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : const Color(0xFF202238);
    final secondaryColor =
        isDark ? Colors.white70 : const Color(0xFF74788D);
    final cardColor = isDark ? const Color(0xFF1C1C2C) : Colors.white;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'Quiz',
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
              constraints: const BoxConstraints(maxWidth: 720),
              child: _questions.isEmpty
                  ? _fallbackView(textColor, secondaryColor)
                  : _quizView(
                      textColor: textColor,
                      secondaryColor: secondaryColor,
                      cardColor: cardColor,
                      isDark: isDark,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quizView({
    required Color textColor,
    required Color secondaryColor,
    required Color cardColor,
    required bool isDark,
  }) {
    final question = _questions[_currentIndex];
    final selected = _answers[_currentIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
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
              Icon(
                _submitted
                    ? Icons.fact_check_rounded
                    : Icons.quiz_rounded,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 16),
              Text(
                _submitted ? 'Your score: $_score / ${_questions.length}'
                    : 'Put your knowledge to work',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _submitted
                    ? 'Review each answer below, or try the quiz again.'
                    : 'Choose one answer per question. '
                        'You can change your choices before submitting.',
                style: const TextStyle(
                  color: Colors.white70,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _submitted
              ? 'Review ${_currentIndex + 1} of ${_questions.length}'
              : 'Question ${_currentIndex + 1} of ${_questions.length}'
                  ' • $_answeredCount answered',
          style: const TextStyle(
            color: _primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: _submitted ? 1 : _answeredCount / _questions.length,
          color: _primary,
          backgroundColor: _primary.withAlpha(25),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            question.question,
            style: TextStyle(
              color: textColor,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < question.options.length; i++) ...[
          _optionTile(
            index: i,
            question: question,
            selected: selected,
            textColor: textColor,
            cardColor: cardColor,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
        ],
        if (_submitted) ...[
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: (selected == question.correctIndex ? _green : _red)
                  .withAlpha(20),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              selected == question.correctIndex
                  ? 'Correct — your answer matches the answer key.'
                  : 'Correct answer: '
                      '${String.fromCharCode(65 + question.correctIndex)}) '
                      '${question.options[question.correctIndex]}',
              style: TextStyle(
                color: textColor,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ],
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _currentIndex == 0
                  ? null
                  : () {
                      setState(() => _currentIndex--);
                    },
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Previous'),
            ),
            OutlinedButton.icon(
              onPressed: _currentIndex == _questions.length - 1
                  ? null
                  : () {
                      setState(() => _currentIndex++);
                    },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Next'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _submitted ? _retry : _submit,
          icon: Icon(
            _submitted ? Icons.replay_rounded : Icons.check_rounded,
          ),
          label: Text(_submitted ? 'Retry Quiz' : 'Submit Quiz'),
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            minimumSize: const Size.fromHeight(54),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'AI-generated questions and answer keys may contain mistakes. '
          'Check your study material if an answer seems incorrect.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryColor,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _optionTile({
    required int index,
    required _QuizQuestion question,
    required int? selected,
    required Color textColor,
    required Color cardColor,
    required bool isDark,
  }) {
    final isSelected = selected == index;
    final isCorrect = _submitted && question.correctIndex == index;
    final isWrong = _submitted && isSelected && !isCorrect;

    final accent = isCorrect
        ? _green
        : isWrong
            ? _red
            : isSelected
                ? _primary
                : (isDark ? const Color(0xFF45455B) : Colors.grey.shade300);

    final highlighted = isSelected || isCorrect;

    return Semantics(
      selected: isSelected,
      button: true,
      child: Material(
        color: highlighted ? accent.withAlpha(20) : cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: accent,
            width: highlighted ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _submitted
              ? null
              : () {
                  setState(() {
                    _answers[_currentIndex] = index;
                  });
                },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${String.fromCharCode(65 + index)}.',
                  style: TextStyle(
                    color: highlighted ? accent : textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    question.options[index],
                    style: TextStyle(
                      color: textColor,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isCorrect
                      ? Icons.check_circle_rounded
                      : isWrong
                          ? Icons.cancel_rounded
                          : isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                  color: accent,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackView(Color textColor, Color secondaryColor) {
    final empty = widget.quiz.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.quiz_outlined,
          size: 48,
          color: _primary,
        ),
        const SizedBox(height: 20),
        Text(
          empty ? 'No quiz to display' : 'Quiz text',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          empty
              ? 'Go back and generate a quiz from your study material.'
              : 'This quiz could not be converted into interactive '
                  'questions. Its original text is shown below. '
                  'Generate a new quiz to try again.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: secondaryColor,
            height: 1.5,
          ),
        ),
        if (!empty) ...[
          const SizedBox(height: 24),
          SelectableText(
            widget.quiz,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              height: 1.7,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;

  const _QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
  });
}