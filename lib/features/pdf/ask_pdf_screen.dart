import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'pdf_viewer_screen.dart';
import '../../core/services/openrouter_service.dart';
import '../../core/services/pdf_question_service.dart';
import '../../repositories/pdf_chat_repository.dart';
class AskPdfScreen extends StatefulWidget {
  final String pdfId;
  final String fileName;
  final String ownerId;
  final String pdfPath;

  const AskPdfScreen({
    super.key,
    required this.pdfId,
    required this.fileName,
    required this.ownerId,
    this.pdfPath = '',
  });

  @override
  State<AskPdfScreen> createState() => _AskPdfScreenState();
}

class _QuestionTurn {
  final String id;
  final String question;
  final PdfAnswer? answer;
  final String? error;
  final bool saved;

  const _QuestionTurn({
    required this.id,
    required this.question,
    this.answer,
    this.error,
    this.saved = false,
  });
}

class _AskPdfScreenState extends State<AskPdfScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _service = PdfQuestionService();

  final List<_QuestionTurn> _turns = [];
  bool _busy = false;

  static const _purple = Color(0xFF6750E8);

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _sameUser =>
      FirebaseAuth.instance.currentUser?.uid == widget.ownerId;

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  final _chatRepository = PdfChatRepository();

bool _loadingHistory = true;
String? _historyError;

@override
void initState() {
  super.initState();
  _loadHistory();
}

Future<void> _loadHistory() async {
  setState(() {
    _loadingHistory = true;
    _historyError = null;
  });

  try {
    if (!_sameUser) {
      throw StateError('Please sign in again.');
    }

    final entries = await _chatRepository.load(widget.pdfId);

    if (!mounted) return;

    if (!_sameUser) {
      throw StateError('Your session changed. Please sign in again.');
    }

    setState(() {
      _turns
        ..clear()
        ..addAll(
          entries.map(
            (entry) => _QuestionTurn(
              id: entry.id,
              question: entry.question,
              answer: entry.answer,
              saved: true,
            ),
          ),
        );
    });

    _scrollToBottom();
  } catch (error) {
    if (!mounted) return;

    setState(() {
      _historyError = error is StateError
          ? error.message.toString()
          : 'Could not load history. Check your connection '
              'and chat-history rules.';
    });
  } finally {
    if (mounted) {
      setState(() => _loadingHistory = false);
    }
  }
}

  void _openSourcePage(int pageNumber) {
  if (!_sameUser) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your session changed. Please sign in again.'),
      ),
    );
    return;
  }

  if (widget.pdfPath.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'The original PDF is not available on this device. '
          'You can still read the supporting quote.',
        ),
      ),
    );
    return;
  }

  if (pageNumber < 1) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This source has an invalid page number.'),
      ),
    );
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PdfViewerScreen(
        pdfPath: widget.pdfPath,
        initialPageNumber: pageNumber,
      ),
    ),
  );
}


  String _errorText(Object error) {
    if (error is StateError) return error.message.toString();

    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Access denied. Check your verified login and PDF page rules.';
      }

      if (error.code == 'unavailable') {
        return 'Could not load PDF pages. Check your internet connection.';
      }
    }

    return 'The question could not be answered. Please try again.';
  }

  Future<void> _ask({int? retryIndex}) async {
  if (_busy || _loadingHistory || _historyError != null) return;

  if (!_sameUser) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in again.')),
    );
    return;
  }

  final previous = retryIndex == null ? null : _turns[retryIndex];

  final question = previous?.question ?? _controller.text.trim();

  if (question.isEmpty) return;

  if (question.length > 1000) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Keep your question under 1,000 characters.'),
      ),
    );
    return;
  }

  final id = previous?.id ?? _chatRepository.createId(widget.pdfId);
  final index = retryIndex ?? _turns.length;

  // Preserve a generated answer if only its Firestore save failed.
  PdfAnswer? answer = previous?.answer;

  FocusScope.of(context).unfocus();

  setState(() {
    _busy = true;

    final turn = _QuestionTurn(
      id: id,
      question: question,
      answer: answer,
    );

    if (retryIndex == null) {
      _turns.add(turn);
      _controller.clear();
    } else {
      _turns[index] = turn;
    }
  });

  _scrollToBottom();

  try {
    final result = answer ??
        await _service.ask(
          pdfId: widget.pdfId,
          ownerId: widget.ownerId,
          question: question,
        );

    answer = result;

    if (!mounted) return;

    if (!_sameUser) {
      throw StateError('Your session changed. Please sign in again.');
    }

    // Show the answer while its history entry is being saved.
    setState(() {
      _turns[index] = _QuestionTurn(
        id: id,
        question: question,
        answer: result,
      );
    });

    await _chatRepository.save(
      pdfId: widget.pdfId,
      ownerId: widget.ownerId,
      messageId: id,
      question: question,
      answer: result,
    );

    if (!mounted) return;

    if (!_sameUser) {
      setState(_turns.clear);
      return;
    }

    setState(() {
      _turns[index] = _QuestionTurn(
        id: id,
        question: question,
        answer: result,
        saved: true,
      );
    });
  } catch (error) {
    if (!mounted) return;

    if (!_sameUser) {
      setState(_turns.clear);
      return;
    }

    setState(() {
      _turns[index] = _QuestionTurn(
        id: id,
        question: question,
        answer: answer,
        error: answer == null
            ? _errorText(error)
            : 'Your answer is available, but saving history failed. '
                'Check your connection and Firestore rules, then retry.',
      );
    });
  } finally {
    if (mounted) {
      setState(() => _busy = false);
      _scrollToBottom();
    }
  }
}

  Widget _turnCard(int index) {
    final turn = _turns[index];
    final answer = turn.answer;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _purple,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              turn.question,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (answer != null) ...[

                      Text(
                            turn.saved
                                ? 'Saved to history'
                                : turn.error != null
                                    ? 'Not saved'
                                    : 'Saving...',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),

                          if (turn.error != null) ...[
                            Text(
                              turn.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _busy ? null : () => _ask(retryIndex: index),
                              icon: const Icon(Icons.cloud_upload_outlined),
                              label: const Text('Retry saving'),
                            ),
                            const SizedBox(height: 8),
                          ],

                    SelectableText(
                      answer.answer,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                    if (answer.sources.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Supporting passages',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      for (final source in answer.sources)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text('Page ${source.pageNumber}'),
                        leading: const Icon(
                          Icons.find_in_page_outlined,
                          color: _purple,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SelectableText(
                                  source.quote,
                                  style: const TextStyle(height: 1.5),
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openSourcePage(
                                      source.pageNumber,
                                    ),
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                    label: Text(
                                      'Open page ${source.pageNumber}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else if (turn.error != null) ...[
                    Text(
                      turn.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed:
                          _busy ? null : () => _ask(retryIndex: index),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ] else
                    const Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Finding passages and preparing an answer...',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    if (_loadingHistory || _historyError != null) {
  return Scaffold(
    appBar: AppBar(title: const Text('Ask My PDF')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _loadingHistory
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _historyError!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loadHistory,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry loading history'),
                  ),
                ],
              ),
      ),
    ),
  );
}

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ask My PDF'),
            Text(
              widget.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text(
                    'Ask a specific question. Each question is answered '
                    'independently. Check the supporting quotes; '
                    'AI answers can contain mistakes.',
                    style: TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
                Expanded(
                  child: _turns.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.question_answer_outlined,
                                  size: 64,
                                  color: _purple,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'What would you like to understand?',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Use a topic from your document, such as '
                                  '"How does backpropagation work?"',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _turns.length,
                          itemBuilder: (_, index) => _turnCard(index),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_busy,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 1000,
                          decoration: InputDecoration(
                            hintText: 'Ask about this PDF...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: IconButton.filled(
                          tooltip: 'Ask question',
                          onPressed: _busy ? null : () => _ask(),
                          style: IconButton.styleFrom(
                            backgroundColor: _purple,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}