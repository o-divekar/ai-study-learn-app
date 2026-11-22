import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/services/document_text_service.dart';
import '../../core/services/openrouter_service.dart';
import '../../core/services/pdf_service.dart';
import '../../repositories/pdf_repository.dart';
import '../../repositories/summary_repository.dart';
import '../security/upload_text_review_screen.dart';

class UploadPdfScreen extends StatefulWidget {
  const UploadPdfScreen({super.key});

  @override
  State<UploadPdfScreen> createState() => _UploadPdfScreenState();
}

class _UploadPdfScreenState extends State<UploadPdfScreen> {
  final PdfRepository pdfRepository = PdfRepository();
  final PdfService pdfService = PdfService();
  final SummaryRepository summaryRepository = SummaryRepository();
  final OpenRouterService aiService = OpenRouterService();
  final DocumentTextService documentTextService =
      DocumentTextService();

  static const _primaryColor = Color(0xFF6750E8);
  static const _maxFileBytes = 20 * 1024 * 1024;
  static const _maxTextBytes = 700000;

  static const _allowedTypes = [
    'pdf',
    'txt',
    'md',
    'csv',
    'docx',
    'doc',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'rtf',
    'jpg',
    'jpeg',
    'png',
  ];

  File? _selectedFile;

  String? _ownerId;
  String? _fileName;
  String? _uploadId;
  String? _extractedText;
  String? _generatedSummary;
  String? _error;

  List<PdfPageText>? _extractedPages;

  bool _isBusy = false;
  bool _textReviewed = false;
  bool _documentSaved = false;
  bool _summarySaved = false;
  bool _metadataApproved = false;

  String _status = 'Select a document to get started.';

  String get _fileType {
    final name = _fileName;
    return name == null ? '' : DocumentTextService.extension(name);
  }

  bool get _isPdf => _fileType == 'pdf';

  bool get _supportsText =>
      _isPdf ||
      DocumentTextService.supportedTextTypes.contains(_fileType);

  bool get _finished =>
      _documentSaved && (!_supportsText || _summarySaved);

  void _setStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
  }

  void _checkSession() {
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted ||
        user == null ||
        user.uid != _ownerId ||
        !user.emailVerified) {
      throw StateError(
        'Your session changed. Please sign in again '
        'with your verified account.',
      );
    }
  }

  String _combinePages(List<PdfPageText> pages) {
    return pages
        .where((page) => page.hasText)
        .map((page) => 'Page ${page.pageNumber}\n${page.text}')
        .join('\n\n');
  }

  void _validateReviewedText(String text) {
    if (text.trim().isEmpty) {
      throw StateError(
        'No reviewed text remains. Please select the document again.',
      );
    }

    if (utf8.encode(text).length > _maxTextBytes) {
      throw StateError(
        'The reviewed text is too large for this workflow. '
        'Select a shorter document or chapter.',
      );
    }
  }

  Future<void> pickPdf() async {
    if (_isBusy) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null || !user.emailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please sign in with a verified email first.',
          ),
        ),
      );
      return;
    }

    final selectionOwnerId = user.uid;

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _allowedTypes,
        allowMultiple: false,
      );

      if (!mounted || result == null) return;

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null ||
          currentUser.uid != selectionOwnerId ||
          !currentUser.emailVerified) {
        throw StateError(
          'Your session changed. Please sign in again.',
        );
      }

      final pickedFile = result.files.single;
      final type = DocumentTextService.extension(pickedFile.name);
      final sourcePath = pickedFile.path;

      if (!_allowedTypes.contains(type)) {
        throw StateError('This document format is not supported.');
      }

      if (sourcePath == null || sourcePath.trim().isEmpty) {
        throw StateError(
          'The selected document could not be accessed.',
        );
      }

      final source = File(sourcePath);

      if (!await source.exists()) {
        throw StateError(
          'The selected file is no longer available.',
        );
      }

      final size = await source.length();

      if (size == 0) {
        throw StateError('The selected file is empty.');
      }

      if (size > _maxFileBytes) {
        throw StateError('Select a document up to 20 MB.');
      }

      if (!mounted) return;

      final latestUser = FirebaseAuth.instance.currentUser;

      if (latestUser == null ||
          latestUser.uid != selectionOwnerId ||
          !latestUser.emailVerified) {
        throw StateError(
          'Your session changed. Please sign in again.',
        );
      }

      // Reset only after a valid new selection.
      setState(() {
        _ownerId = selectionOwnerId;
        _uploadId = FirebaseFirestore.instance
            .collection('pdf_notes')
            .doc()
            .id;

        _fileName = pickedFile.name;
        _selectedFile = null;
        _extractedText = null;
        _extractedPages = null;
        _generatedSummary = null;

        _textReviewed = false;
        _documentSaved = false;
        _summarySaved = false;
        _metadataApproved = false;

        _status = 'Saving a local copy...';
      });

      final documents = await getApplicationDocumentsDirectory();
      _checkSession();

      final userFolder = Directory(
        '${documents.path}/study_pdfs/$selectionOwnerId',
      );

      await userFolder.create(recursive: true);
      _checkSession();

      final documentFolder = await userFolder.createTemp('document_');
      _checkSession();

      var safeName = pickedFile.name.replaceAll(
        RegExp(r'[\\/:*?"<>|\x00-\x1F]'),
        '_',
      );

      if (safeName.trim().isEmpty ||
          safeName == '.' ||
          safeName == '..') {
        safeName = 'document.$type';
      }

      final copiedFile = await source.copy(
        '${documentFolder.path}/$safeName',
      );

      _checkSession();

      setState(() {
        _selectedFile = copiedFile;
      });

      await _processDocument();
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _extractText() async {
    if (_extractedText != null) return;

    _checkSession();

    final file = _selectedFile;

    if (file == null) {
      throw StateError('Please select a document first.');
    }

    if (_isPdf) {
      _setStatus('Extracting text from each PDF page...');

      final pages = await pdfService.extractPages(file.path);
      _checkSession();

      if (pages.isEmpty || !pages.any((page) => page.hasText)) {
        throw StateError(
          'No readable text was found. This PDF may contain '
          'scanned images and require OCR.',
        );
      }

      setState(() {
        _extractedPages = pages;
        _extractedText = _combinePages(pages);
      });
    } else {
      _setStatus('Extracting document text locally...');

      final text = await documentTextService.extractText(
        file.path,
        _fileType,
      );

      _checkSession();

      if (text.trim().isEmpty) {
        throw StateError(
          'No readable text was found in this document.',
        );
      }

      setState(() {
        _extractedText = text;
      });
    }
  }

  Future<bool> _reviewExtractedText() async {
    _checkSession();

    if (_textReviewed) return true;

    final text = _extractedText;

    if (text == null) {
      throw StateError(
        'Document text is unavailable. Please select it again.',
      );
    }

    final sections = _isPdf
        ? _extractedPages!
        : [
            PdfPageText(
              pageNumber: 1,
              text: text,
            ),
          ];

    _setStatus('Waiting for your text review...');

    final reviewed =
        await Navigator.of(context).push<List<PdfPageText>>(
      MaterialPageRoute(
        builder: (_) => UploadTextReviewScreen(
          fileName: _fileName!,
          sections: sections,
          isPdf: _isPdf,
        ),
      ),
    );

    if (!mounted) return false;
    _checkSession();

    if (reviewed == null) {
      setState(() {
        _status = 'Review paused. Local file retained.';
        _error = 'No document text or record has been uploaded. '
            'Tap Retry Processing to review again.';
      });
      return false;
    }

    if (reviewed.length != sections.length) {
      throw StateError(
        'The reviewed sections do not match the document.',
      );
    }

    for (var index = 0; index < reviewed.length; index++) {
      if (reviewed[index].pageNumber != sections[index].pageNumber) {
        throw StateError(
          'The reviewed page numbers do not match the document.',
        );
      }
    }

    if (!reviewed.any((section) => section.hasText)) {
      throw StateError(
        'No text remains after review. Select the document again.',
      );
    }

    final reviewedText = _isPdf
        ? _combinePages(reviewed)
        : reviewed.single.text.trim();

    _validateReviewedText(reviewedText);

    setState(() {
      if (_isPdf) {
        _extractedPages = reviewed;
      }

      // Replace original extracted text with approved text.
      _extractedText = reviewedText;
      _textReviewed = true;
      _error = null;
    });

    return true;
  }

  Future<bool> _approveMetadataOnly() async {
    _checkSession();

    if (_metadataApproved) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save without text inspection?'),
        content: const Text(
          'Text extraction and inspection are unavailable for '
          'this format.\n\n'
          'Only the filename, local file path, and document '
          'metadata will be stored in Firestore. No file contents '
          'will be sent to AI.\n\n'
          'The original file remains on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save record'),
          ),
        ],
      ),
    );

    if (!mounted) return false;
    _checkSession();

    if (confirmed != true) {
      setState(() {
        _status = 'Saving paused. Local file retained.';
        _error = 'No document record was saved. '
            'Tap Retry Processing to continue.';
      });
      return false;
    }

    _metadataApproved = true;
    return true;
  }

  Future<void> _saveDocument() async {
    _checkSession();

    if (_documentSaved) return;

    final file = _selectedFile!;
    final uploadId = _uploadId!;
    final ownerId = _ownerId!;
    final fileName = _fileName!;

    final reference = FirebaseFirestore.instance
        .collection('pdf_notes')
        .doc(uploadId);

    if (_supportsText && !_textReviewed) {
      throw StateError(
        'Review and approve the text before saving.',
      );
    }

    if (_isPdf) {
      _setStatus('Saving approved PDF pages...');

      await pdfRepository.savePdfWithPages(
        documentId: uploadId,
        fileName: fileName,
        pdfPath: file.path,
        userId: ownerId,
        pages: _extractedPages!,
      );

      _checkSession();

      await reference.update({
        'fileType': 'pdf',
        'localPath': file.path,
        'textReviewed': true,
        'reviewedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      _setStatus(
        _supportsText
            ? 'Saving approved document text...'
            : 'Saving document metadata...',
      );

      // Save the record and approved text together.
      await FirebaseFirestore.instance.runTransaction(
        (transaction) async {
          _checkSession();

          final existing = await transaction.get(reference);

          _checkSession();

          if (existing.exists &&
              existing.data()?['userId'] != ownerId) {
            throw StateError(
              'This document belongs to another account.',
            );
          }

          transaction.set(
            reference,
            {
              'fileName': fileName,
              'fileType': _fileType,
              'localPath': file.path,

              // Retained for compatibility with existing screens.
              'pdfPath': file.path,

              'userId': ownerId,
              'textStorage': _supportsText ? 'document' : 'none',
              'extractionStatus':
                  _supportsText ? 'ready' : 'unsupported',
              'textReviewed': _supportsText && _textReviewed,

              if (_supportsText) ...{
                'extractedText': _extractedText!,
                'reviewedAt': FieldValue.serverTimestamp(),
              },

              if (!existing.exists)
                'createdAt': FieldValue.serverTimestamp(),

              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        },
      );
    }

    _checkSession();

    setState(() {
      _documentSaved = true;
    });
  }

  Future<void> _generateAndSaveSummary() async {
    _checkSession();

    if (!_textReviewed || !_documentSaved) {
      throw StateError(
        'The approved document text must be saved first.',
      );
    }

    final reviewedText = _extractedText!;
    _validateReviewedText(reviewedText);

    if (_generatedSummary == null) {
      _setStatus('Generating a summary from approved text...');

      // Only approved text is passed to AI.
      final summary = await aiService.generateSummary(reviewedText);

      _checkSession();

      if (summary.trim().isEmpty) {
        throw StateError(
          'The AI returned an empty summary. Please retry.',
        );
      }

      setState(() {
        _generatedSummary = summary.trim();
      });
    }

    if (!_summarySaved) {
      _setStatus('Saving your summary...');

      await summaryRepository.saveSummary(
        documentId: _uploadId!,
        pdfId: _uploadId!,
        userId: _ownerId!,
        fileName: _fileName!,
        summary: _generatedSummary!,
      );

      _checkSession();

      setState(() {
        _summarySaved = true;
      });
    }
  }

  Future<void> _processDocument() async {
    _checkSession();

    if (_selectedFile == null ||
        _fileName == null ||
        _uploadId == null) {
      throw StateError('Please select a document first.');
    }

    if (_supportsText) {
      await _extractText();

      if (!await _reviewExtractedText()) return;

      _checkSession();
      _validateReviewedText(_extractedText!);
    } else {
      if (!await _approveMetadataOnly()) return;
    }

    await _saveDocument();

    if (_supportsText) {
      await _generateAndSaveSummary();
    }

    _checkSession();

    setState(() {
      _error = null;
      _status = _supportsText
          ? 'Your reviewed document and AI summary are ready.'
          : 'Document record saved. AI text extraction '
              'is unavailable for this format.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _supportsText
              ? 'Approved text and summary saved.'
              : 'Document record saved.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _retry() async {
    if (_isBusy || _selectedFile == null || _finished) return;

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      await _processDocument();
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _handleError(Object error) {
    if (!mounted) return;

    String message;

    if (error is StateError) {
      message = error.message.toString();
    } else if (error is FirebaseException) {
      message = error.code == 'permission-denied'
          ? 'Access was denied. Check your verified login '
              'and Firestore rules.'
          : 'Saving could not be completed. Check your '
              'connection and retry.';
    } else if (error is FileSystemException) {
      message = 'The document could not be copied or read. '
          'Check device storage and select the file again.';
    } else {
      message = _documentSaved
          ? 'Your document is saved, but summary processing '
              'could not finish. Please retry.'
          : 'Processing could not finish. Retry or select '
              'another document.';
    }

    // Do not log extracted text or raw provider responses.
    setState(() {
      _error = message;
      _status = _documentSaved
          ? 'Document saved. Summary needs attention.'
          : 'Processing could not finish.';
    });
  }

  Widget _step({
    required String title,
    required bool complete,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            complete
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: complete
                ? const Color(0xFF209C86)
                : Colors.grey,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);

    final secondaryColor = isDark
        ? const Color(0xFFB3B5C9)
        : const Color(0xFF74788D);

    final cardColor =
        isDark ? const Color(0xFF1C1C2C) : Colors.white;

    final emptyPages =
        _extractedPages?.where((page) => !page.hasText).length ?? 0;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'Upload Document',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(26),
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
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.upload_file_rounded,
                          size: 44,
                          color: Colors.white,
                        ),
                        SizedBox(height: 20),
                        Text(
                          'Turn reading into learning',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Select a document, review its extracted '
                          'text, and generate a study summary.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _fileName ?? 'Choose your document',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Files up to 20 MB.\n\n'
                          'AI summaries: text-based PDF, TXT, '
                          'Markdown, CSV, and DOCX.\n\n'
                          'Other listed formats are saved as local '
                          'files with a document record. They do '
                          'not generate summaries.',
                          style: TextStyle(
                            color: secondaryColor,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        ElevatedButton.icon(
                          onPressed: _isBusy ? null : pickPdf,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: Text(
                            _fileName == null
                                ? 'Select Document'
                                : 'Select Another Document',
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
                        const SizedBox(height: 22),

                        if (_isBusy) ...[
                          const LinearProgressIndicator(
                            color: _primaryColor,
                          ),
                          const SizedBox(height: 16),
                        ],

                        Text(
                          _status,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),

                        if (_fileName != null) ...[
                          const SizedBox(height: 16),
                          _step(
                            title: 'Local document copy saved',
                            complete: _selectedFile != null,
                          ),

                          if (_supportsText) ...[
                            _step(
                              title: _isPdf
                                  ? _extractedPages == null
                                      ? 'Extract text from PDF pages'
                                      : '${_extractedPages!.length} '
                                          'PDF pages processed'
                                  : 'Document text extracted',
                              complete: _extractedText != null,
                            ),
                            _step(
                              title: 'Text reviewed and approved',
                              complete: _textReviewed,
                            ),
                          ],

                          _step(
                            title: _supportsText
                                ? 'Document and approved text saved'
                                : 'Document metadata saved',
                            complete: _documentSaved,
                          ),

                          if (_isPdf && emptyPages > 0)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                '$emptyPages pages currently contain '
                                'no text. They may be blank, require '
                                'OCR, or have been cleared during '
                                'review. Text inside images is not '
                                'automatically included.',
                                style: TextStyle(
                                  color: secondaryColor,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),

                          if (_supportsText) ...[
                            _step(
                              title: 'AI summary generated',
                              complete: _generatedSummary != null,
                            ),
                            _step(
                              title: 'AI summary saved',
                              complete: _summarySaved,
                            ),
                          ],
                        ],

                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              height: 1.5,
                            ),
                          ),
                          if (_selectedFile != null && !_finished) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _isBusy ? null : _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(
                                _generatedSummary != null &&
                                        !_summarySaved
                                    ? 'Retry Saving Summary'
                                    : 'Retry Processing',
                              ),
                            ),
                          ],
                        ],

                        if (_documentSaved && _uploadId != null) ...[
                          const SizedBox(height: 18),
                          SelectableText(
                            'Document ID: $_uploadId',
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (_generatedSummary != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome,
                                color: _primaryColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Summary of approved text',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            _generatedSummary!,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _summarySaved
                                ? 'Saved to AI Summaries.'
                                : 'Summary generated. Saving has '
                                    'not been confirmed yet.',
                            style: TextStyle(
                              color: _summarySaved
                                  ? const Color(0xFF209C86)
                                  : secondaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),
                  Text(
                    _isBusy
                        ? 'Keep this screen open while processing.'
                        : 'Find saved documents in My PDFs / '
                            'My Documents and summaries in AI Summaries.\n\n'
                            'Original files remain unchanged on this '
                            'device. Redaction applies to reviewed '
                            'text, not the original file.',
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