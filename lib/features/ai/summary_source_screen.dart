import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'reviewed_text_export_card.dart';

class SummarySourceScreen extends StatefulWidget {
  final String summaryId;
  final String fileName;
  final String ownerId;

  const SummarySourceScreen({
    super.key,
    required this.summaryId,
    required this.fileName,
    required this.ownerId,
  });

  @override
  State<SummarySourceScreen> createState() =>
      _SummarySourceScreenState();
}

class _SourceSection {
  final String title;
  final String text;

  const _SourceSection(this.title, this.text);
}

class _SourceResult {
  final bool reviewed;
  final bool linkedDocument;
  final List<_SourceSection> sections;

  const _SourceResult({
    required this.reviewed,
    required this.linkedDocument,
    required this.sections,
  });
}

class _SummarySourceScreenState extends State<SummarySourceScreen> {
  late Future<_SourceResult> _sourceFuture;

  static const _purple = Color(0xFF6750E8);
  static const _server = GetOptions(source: Source.server);

  @override
  void initState() {
    super.initState();
    _sourceFuture = _loadSource();
  }

  void _checkSession() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null ||
        user.uid != widget.ownerId ||
        !user.emailVerified) {
      throw StateError(
        'Please sign in with the verified account '
        'that owns this summary.',
      );
    }
  }

  String? _nonEmptyString(dynamic value) {
    return value is String && value.trim().isNotEmpty
        ? value
        : null;
  }

  void _checkSize(String text) {
    if (utf8.encode(text).length > 2000000) {
      throw StateError(
        'This source is too large for the current text viewer.',
      );
    }
  }

  Future<_SourceResult> _loadSource() async {
    _checkSession();

    final firestore = FirebaseFirestore.instance;
    final summarySnapshot = await firestore
        .collection('summaries')
        .doc(widget.summaryId)
        .get(_server);

    _checkSession();

    final summary = summarySnapshot.data();

    if (summary == null) {
      throw StateError(
        'This summary no longer exists.',
      );
    }

    if (summary['userId'] != widget.ownerId) {
      throw StateError('You cannot access this summary.');
    }

    // Security Inspector stores the approved input in the summary.
    final reviewedText = _nonEmptyString(summary['reviewedText']);

    if (reviewedText != null) {
      _checkSize(reviewedText);

      return _SourceResult(
        reviewed: summary['textReviewed'] == true,
        linkedDocument: false,
        sections: [
          _SourceSection('Saved source text', reviewedText),
        ],
      );
    }

    // Uploaded document summaries link to pdf_notes through pdfId.
    final pdfId = _nonEmptyString(summary['pdfId']);

    if (pdfId == null || pdfId.contains('/')) {
      throw StateError(
        'Source unavailable. This summary has no saved '
        'source text or linked document.',
      );
    }

    final documentReference =
        firestore.collection('pdf_notes').doc(pdfId);

    final documentSnapshot = await documentReference.get(_server);

    _checkSession();

    final document = documentSnapshot.data();

    if (document == null) {
      throw StateError(
        'Source unavailable. The linked document may '
        'have been deleted.',
      );
    }

    if (document['userId'] != widget.ownerId) {
      throw StateError('You cannot access this document.');
    }

    final status = document['extractionStatus'];

    if (status == 'processing' ||
        status == 'pending' ||
        status == 'deleting' ||
        status == 'failed') {
      throw StateError(
        'The linked document is not ready to display. '
        'Finish processing it or try again later.',
      );
    }

    final reviewed = document['textReviewed'] == true;

    if (document['textStorage'] == 'pages') {
      if (status != 'ready') {
        throw StateError('The PDF pages are not ready.');
      }

      final pageCount = document['pageCount'];

      if (pageCount is! int || pageCount < 1 || pageCount > 200) {
        throw StateError(
          'This viewer supports documents with 1 to 200 pages.',
        );
      }

      final pagesSnapshot = await documentReference
          .collection('pages')
          .limit(201)
          .get(_server);

      _checkSession();

      if (pagesSnapshot.docs.length != pageCount) {
        throw StateError(
          'Some saved pages are missing or incomplete. '
          'Please retry after document processing finishes.',
        );
      }

      final pages = <int, String>{};
      var totalBytes = 0;

      for (final snapshot in pagesSnapshot.docs) {
        final page = snapshot.data();
        final number = page['pageNumber'];
        final text = page['text'];

        if (page['userId'] != widget.ownerId ||
            number is! int ||
            number < 1 ||
            number > pageCount ||
            text is! String ||
            pages.containsKey(number)) {
          throw StateError(
            'The saved page data is invalid or incomplete.',
          );
        }

        totalBytes += utf8.encode(text).length;

        if (totalBytes > 2000000) {
          throw StateError(
            'This source is too large for the current viewer.',
          );
        }

        pages[number] = text;
      }

      return _SourceResult(
        reviewed: reviewed,
        linkedDocument: true,
        sections: List.generate(
          pageCount,
          (index) => _SourceSection(
            'Page ${index + 1}',
            pages[index + 1]!,
          ),
        ),
      );
    }

    // TXT, DOCX, Markdown, CSV, or older combined-text records.
    final text = _nonEmptyString(document['extractedText']);

    if (text == null) {
      throw StateError(
        'Source unavailable. This document has no saved text.',
      );
    }

    _checkSize(text);

    return _SourceResult(
      reviewed: reviewed,
      linkedDocument: true,
      sections: [
        _SourceSection('Document text', text),
      ],
    );
  }

  void _retry() {
    setState(() {
      _sourceFuture = _loadSource();
    });
  }

  String _errorMessage(Object? error) {
    if (error is StateError) {
      return error.message.toString();
    }

    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Access was denied. Check your verified '
            'login and Firestore rules.';
      }

      if (error.code == 'unavailable') {
        return 'Connect to the internet to load the saved source.';
      }
    }

    return 'The source could not be loaded. Please retry.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Source text'),
      ),
      body: SafeArea(
        child: FutureBuilder<_SourceResult>(
          future: _sourceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: _purple),
              );
            }

            final user = FirebaseAuth.instance.currentUser;

            if (snapshot.hasError ||
                user?.uid != widget.ownerId ||
                user?.emailVerified != true) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 48,
                       color: _purple,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        snapshot.hasError
                            ? _errorMessage(snapshot.error)
                            : 'Your session changed. Sign in again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final result = snapshot.data!;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: result.sections.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.fileName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Chip(
                              avatar: Icon(
                                result.reviewed
                                    ? Icons.fact_check_outlined
                                    : Icons.info_outline,
                                size: 18,
                              ),
                              label: Text(
                                result.reviewed
                                    ? 'Reviewed text'
                                    : 'Review status unavailable',
                              ),
                            ),

                              ReviewedTextExportCard(
                              key: ObjectKey(result),
                              ownerId: widget.ownerId,
                              text: result.sections.map((section) {
                                return '${section.title}\n${section.text}';
                              }).join('\n\n'),
                            ),

                            const SizedBox(height: 10),
                            Text(
                              result.reviewed
                                  ? 'This is saved reviewed text. '
                                      'It may contain redactions or edits '
                                      'and can differ from the original file.'
                                  : 'This older record has no review '
                                      'confirmation. Its text may contain '
                                      'unredacted information.',
                              style: const TextStyle(height: 1.5),
                            ),
                            if (result.linkedDocument) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'This displays the linked document’s '
                                'currently saved text. If it was reprocessed, '
                                'it may differ from the text originally '
                                'used for this summary.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }

                    final section = result.sections[index - 1];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              section.title,
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              section.text.trim().isEmpty
                                  ? 'No saved text on this page.'
                                  : section.text,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}