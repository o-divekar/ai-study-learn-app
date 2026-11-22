import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfPath;
  final int initialPageNumber;

  const PdfViewerScreen({
    super.key,
    required this.pdfPath,
    this.initialPageNumber = 1,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late Future<String?> _fileCheck;

  int _viewerVersion = 0;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();
    _fileCheck = _checkFile();
  }

 @override
void didUpdateWidget(covariant PdfViewerScreen oldWidget) {
  super.didUpdateWidget(oldWidget);

  if (oldWidget.pdfPath != widget.pdfPath ||
      oldWidget.initialPageNumber != widget.initialPageNumber) {
    _viewerVersion++;
    _fileCheck = _checkFile();
  }
}

  String get _fileName {
    final normalized = widget.pdfPath.replaceAll('\\', '/');
    final name = normalized.split('/').last;

    return name.isEmpty ? 'PDF document' : name;
  }

  Future<String?> _checkFile() async {
    if (widget.pdfPath.trim().isEmpty) {
      return 'This record has no PDF file path. '
          'Return to Home and select the document again '
          'using Upload PDF.';
    }

    try {
      final file = File(widget.pdfPath);

      if (!await file.exists()) {
        return 'This PDF is no longer available at its saved location '
            'on this device. It may have been removed from the cache '
            'or selected on another device.\n\n'
            'Return to Home and select the original PDF again.';
      }

      if (await file.length() == 0) {
        return 'This file is empty. Please select a valid PDF.';
      }

      return null;
    } on FileSystemException {
      return 'The app could not access this file. '
          'Please select the PDF again using Upload PDF.';
    } catch (e) {
      debugPrint('PDF file check failed: $e');

      return 'The file could not be checked. Please try again.';
    }
  }

  void _retry() {
    setState(() {
      _viewerVersion++;
      _fileCheck = _checkFile();
    });
  }

  Widget _loadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: _primaryColor,
          ),
          SizedBox(height: 18),
          Text('Opening your PDF...'),
        ],
      ),
    );
  }

  Widget _errorView({
    required String title,
    required String message,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C2C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _primaryColor.withAlpha(22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: _primaryColor,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? Colors.white
                        : const Color(0xFF202238),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFFB3B5C9)
                        : const Color(0xFF74788D),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('GO BACK'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF11111D)
        : const Color(0xFFF5F5FF);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'PDF Viewer',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: backgroundColor,
        foregroundColor:
            isDark ? Colors.white : const Color(0xFF202238),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1C1C2C)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE76D78).withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Color(0xFFE76D78),
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<String?>(
                future: _fileCheck,
                builder: (context, snapshot) {
                  if (snapshot.connectionState !=
                      ConnectionState.done) {
                    return _loadingView();
                  }

                  if (snapshot.hasError) {
                    return _errorView(
                      title: 'Could not access PDF',
                      message:
                          'The file could not be checked. Please retry.',
                    );
                  }

                  final message = snapshot.data;

                  if (message != null) {
                    return _errorView(
                      title: 'PDF unavailable',
                      message: message,
                    );
                  }

                  return PdfViewer.file(
                  widget.pdfPath,
                  initialPageNumber:
                      widget.initialPageNumber < 1 ? 1 : widget.initialPageNumber,
                  key: ValueKey(
                    '${widget.pdfPath}:${widget.initialPageNumber}:$_viewerVersion',
                  ),
                    params: PdfViewerParams(
                      loadingBannerBuilder: (
                        context,
                        bytesDownloaded,
                        totalBytes,
                      ) {
                        return _loadingView();
                      },
                      errorBannerBuilder: (
                        context,
                        error,
                        stackTrace,
                        documentRef,
                      ) {
                        return _errorView(
                          title: 'Could not open PDF',
                          message:
                              'The document could not be read. '
                              'It may be damaged or use an unsupported '
                              'format. Try again, or select another copy.',
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}