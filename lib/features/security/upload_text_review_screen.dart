import 'package:flutter/material.dart';

import '../../core/services/document_security_service.dart';
import '../../core/services/pdf_service.dart';

class UploadTextReviewScreen extends StatefulWidget {
  final String fileName;
  final List<PdfPageText> sections;
  final bool isPdf;

  const UploadTextReviewScreen({
    super.key,
    required this.fileName,
    required this.sections,
    required this.isPdf,
  });

  @override
  State<UploadTextReviewScreen> createState() =>
      _UploadTextReviewScreenState();
}

class _UploadTextReviewScreenState extends State<UploadTextReviewScreen> {
  final _service = DocumentSecurityService();
  final List<TextEditingController> _controllers = [];
  final List<DocumentSecurityReport> _reports = [];

  bool _approved = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    try {
      final totalLength = widget.sections.fold<int>(
        0,
        (total, section) => total + section.text.length,
      );

      if (totalLength > 300000 || widget.sections.length > 200) {
        throw StateError(
          'Review supports up to 200 sections and '
          '300,000 extracted characters. Select a shorter document.',
        );
      }

      for (final section in widget.sections) {
        final report = _service.inspectText(
          text: section.text,
          fileName: widget.fileName,
        );

        _reports.add(report);

        // Automatically redact all detected matches.
        // Users can edit the resulting text before approving it.
        final redacted = _service.redact(
          report,
          report.findings.map((finding) => finding.id).toSet(),
        );

        _controllers.add(TextEditingController(text: redacted));
      }
    } catch (error) {
      _error = error is StateError
          ? error.message.toString()
          : 'The text could not be prepared for review.';
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _finish() {
    if (!_approved || _error != null) return;

    final result = List.generate(
      widget.sections.length,
      (index) => PdfPageText(
        pageNumber: widget.sections[index].pageNumber,
        text: _controllers[index].text.trim(),
      ),
    );

    if (!result.any((section) => section.hasText)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No text remains. Cancel the upload or keep some study text.',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop<List<PdfPageText>>(result);
  }

  @override
  Widget build(BuildContext context) {
    final findings = _reports.fold<int>(
      0,
      (total, report) => total + report.findings.length,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Review before upload')),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          widget.fileName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '$findings possible text-pattern matches found. '
                          'Detected matches have been replaced with '
                          '[REDACTED]. Review and edit the text below.',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Only the text below will be stored in Firestore '
                          'and used for AI processing. The filename and '
                          'document metadata will also be stored.\n\n'
                          'The original file stays unchanged on this device. '
                          'Opening or sharing it can still reveal the '
                          'original information.\n\n'
                          'These checks can miss sensitive information. '
                          'Images, scripts, and attachments are not scanned.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 20),
                        for (var index = 0;
                            index < widget.sections.length;
                            index++) ...[
                          Text(
                            widget.isPdf
                                ? 'Page ${widget.sections[index].pageNumber}'
                                : 'Document text',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_reports[index].findings.length} '
                            'possible matches',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _controllers[index],
                            minLines: 3,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) {
                              if (_approved) {
                                setState(() => _approved = false);
                              }
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _approved,
                          title: const Text(
                            'I reviewed this text and approve saving it '
                            'to Firestore and sending it to OpenRouter '
                            'and its selected AI provider.',
                          ),
                          onChanged: (value) {
                            setState(() => _approved = value ?? false);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _approved ? _finish : null,
                            child: const Text('Approve and continue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}