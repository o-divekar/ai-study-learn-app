import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/document_converter_service.dart';
import '../pdf/pdf_viewer_screen.dart';

class ReviewedTextExportCard extends StatefulWidget {
  final String text;
  final String ownerId;

  const ReviewedTextExportCard({
    super.key,
    required this.text,
    required this.ownerId,
  });

  @override
  State<ReviewedTextExportCard> createState() =>
      _ReviewedTextExportCardState();
}

class _ReviewedTextExportCardState
    extends State<ReviewedTextExportCard> {
  final _service = DocumentConverterService();

  File? _output;
  bool _busy = false;
  String? _error;
  String _status = 'Review the text before creating a shareable copy.';

  void _checkSession() {
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted ||
        user == null ||
        user.uid != widget.ownerId ||
        !user.emailVerified) {
      throw StateError(
        'Please sign in with the verified account '
        'that owns this document.',
      );
    }
  }

  String _message(Object error) {
    if (error is StateError) {
      return error.message.toString();
    }

    if (error is FileSystemException) {
      return 'The PDF could not be read or saved. '
          'Check available device storage.';
    }

    return 'The operation could not finish. Please try again.';
  }

  Future<void> _createPdf() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      _checkSession();

      final approvedText = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => _ExportReviewScreen(
            initialText: widget.text,
          ),
        ),
      );

      if (!mounted || approvedText == null) return;

      _checkSession();

      setState(() {
        _status = 'Creating your reviewed text PDF...';
      });

      final output = await _service.exportReviewedTextPdf(
        text: approvedText,
        ownerId: widget.ownerId,
      );

      if (!mounted) return;

      _checkSession();

      setState(() {
        _output = output;
        _status = 'PDF created on this device. '
            'Open it to check the result before sharing.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _status = _output == null
              ? 'PDF creation did not finish.'
              : 'The previously created PDF is still available.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<File> _availableOutput() async {
    _checkSession();

    final output = _output;

    if (output == null || !await output.exists()) {
      throw StateError(
        'The exported PDF is unavailable. Create it again.',
      );
    }

    _checkSession();
    return output;
  }

  Future<void> _openPdf() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final output = await _availableOutput();

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfViewerScreen(
            pdfPath: output.path,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveCopy() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final output = await _availableOutput();
      final bytes = await output.readAsBytes();

      _checkSession();

      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save reviewed text PDF',
        fileName: 'reviewed_text_copy.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: bytes,
      );

      if (!mounted || destination == null) return;

      setState(() {
        _status = 'A copy was saved to your selected location.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sharePdf(BuildContext buttonContext) async {
    if (_busy) return;

    final renderObject = buttonContext.findRenderObject();

    final Rect? origin =
        renderObject is RenderBox && renderObject.hasSize
            ? renderObject.localToGlobal(Offset.zero) &
                renderObject.size
            : null;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final output = await _availableOutput();

      await SharePlus.instance.share(
        ShareParams(
          title: 'Share reviewed text PDF',
          subject: 'Reviewed text copy',
          files: [
            XFile(
              output.path,
              mimeType: 'application/pdf',
            ),
          ],
          sharePositionOrigin: origin,
        ),
      );

      // Opening the share sheet does not confirm delivery.
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is StateError
              ? error.message.toString()
              : 'Could not open the sharing menu. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.picture_as_pdf_outlined,
                  color: Color(0xFF6750E8),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Export reviewed text',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Create a new text-only PDF from the text shown here. '
              'Review and edit it before exporting.\n\n'
              'The original file is unchanged. Images and original '
              'layout are not included. Export edits do not change '
              'your saved source or summary.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'Currently supports English text. Some punctuation '
              'is normalized by the PDF exporter.',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _createPdf,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                _output == null
                    ? 'Review and create PDF'
                    : 'Review and create another copy',
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Text(
              _status,
              style: const TextStyle(height: 1.5),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  height: 1.5,
                ),
              ),
            ],
            if (_output != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _openPdf,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open reviewed PDF'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _saveCopy,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save a copy'),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (buttonContext) => FilledButton.icon(
                  onPressed:
                      _busy ? null : () => _sharePdf(buttonContext),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share reviewed PDF'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportReviewScreen extends StatefulWidget {
  final String initialText;

  const _ExportReviewScreen({
    required this.initialText,
  });

  @override
  State<_ExportReviewScreen> createState() =>
      _ExportReviewScreenState();
}

class _ExportReviewScreenState extends State<_ExportReviewScreen> {
  late final TextEditingController _controller;
  bool _approved = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialText,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    final text = _controller.text.trim();

    if (!_approved) return;

    if (text.isEmpty ||
        ('Reviewed text copy\n\n$text').length > 100000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Keep some text and stay within 100,000 characters, '
            'including the PDF heading.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review export text'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Check the text you want to export',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Remove anything you do not want to share. '
              'Existing [REDACTED] placeholders remain unless '
              'you edit them.\n\n'
              'This step does not automatically detect additional '
              'sensitive information or send anything to AI.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              minLines: 12,
              maxLines: 24,
              decoration: const InputDecoration(
                labelText: 'Text for the new PDF',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_approved) {
                  setState(() => _approved = false);
                }
              },
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _approved,
              title: const Text(
                'I reviewed this text and approve creating '
                'a local PDF copy that I can save or share.',
              ),
              onChanged: (value) {
                setState(() => _approved = value ?? false);
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _approved ? _finish : null,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Create reviewed PDF'),
            ),
          ],
        ),
      ),
    );
  }
}