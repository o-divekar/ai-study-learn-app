import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/services/document_security_service.dart';
import '../../core/services/openrouter_service.dart';

class DocumentSecurityScreen extends StatefulWidget {
  const DocumentSecurityScreen({super.key});

  @override
  State<DocumentSecurityScreen> createState() =>
      _DocumentSecurityScreenState();
}

class _DocumentSecurityScreenState
    extends State<DocumentSecurityScreen> {
  final _service = DocumentSecurityService();
  final _previewController = TextEditingController();
  final Set<String> _selectedIds = {};

  DocumentSecurityReport? _report;

  DocumentReference<Map<String, dynamic>>? _summaryReference;

  String? _generationInput;
  String? _generationOwnerId;
  String? _generationFileName;

  String? _error;
  String? _summary;
  String _status = '';

  bool _busy = false;
  bool _previewReady = false;
  bool _reviewed = false;
  bool _saved = false;

  static const _purple = Color(0xFF6750E8);

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  // This only resets the current screen's result.
  // Previously saved summaries remain in Firestore.
  void _resetGeneratedResult() {
    _summary = null;
    _summaryReference = null;
    _generationInput = null;
    _generationOwnerId = null;
    _generationFileName = null;
    _saved = false;
    _status = '';
  }

  void _checkSession(String ownerId) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null ||
        user.uid != ownerId ||
        !user.emailVerified) {
      throw StateError(
        'Your session changed. Please sign in again '
        'with your verified account.',
      );
    }
  }

  Future<void> _scan() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Selecting a document...';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            DocumentSecurityService.supportedExtensions,
        allowMultiple: false,
      );

      if (!mounted || result == null) return;

      final file = result.files.single;
      final path = file.path;

      if (path == null || path.trim().isEmpty) {
        throw StateError(
          'The selected file could not be accessed.',
        );
      }

      setState(() {
        _report = null;
        _selectedIds.clear();
        _previewController.clear();
        _previewReady = false;
        _reviewed = false;
        _resetGeneratedResult();
        _status = 'Inspecting document text locally...';
      });

      // Let the loading indicator paint before parsing.
      await Future<void>.delayed(
        const Duration(milliseconds: 30),
      );

      if (!mounted) return;

      final report = await _service.inspect(
        path: path,
        fileName: file.name,
      );

      if (!mounted) return;

      setState(() {
        _report = report;

        // Select every detected match for redaction by default.
        _selectedIds.addAll(
          report.findings.map((finding) => finding.id),
        );
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'Inspection failed. Try a smaller supported document.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  void _buildPreview() {
    final report = _report;

    if (report == null || _busy) return;

    final redactedText = _service.redact(
      report,
      _selectedIds,
    );

    setState(() {
      _previewController.text = redactedText;
      _previewReady = true;
      _reviewed = false;
      _error = null;
      _resetGeneratedResult();
    });
  }

  Future<void> _showMatch(SecurityFinding finding) async {
    final report = _report;

    if (report == null || _busy) return;

    final match = report.text.substring(
      finding.start,
      finding.end,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(finding.title),
        content: SingleChildScrollView(
          child: SelectableText(match),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _summarise() async {
    if (_busy || !_previewReady || !_reviewed) return;

    final report = _report;
    final user = FirebaseAuth.instance.currentUser;

    if (report == null) return;

    if (user == null || !user.emailVerified) {
      setState(() {
        _error = 'Please sign in with your verified account.';
      });
      return;
    }

    // Capture the reviewed editor text once.
    // Both AI generation and Firestore use this same snapshot.
    final reviewedText = _previewController.text.trim();
    final fileName = report.fileName;
    final ownerId = user.uid;

    if (reviewedText.isEmpty || reviewedText.length > 20000) {
      setState(() {
        _error = 'Keep the reviewed text between 1 and '
            '20,000 characters. You can shorten it in the editor.';
      });
      return;
    }

    final sameRequest =
        _generationInput == reviewedText &&
        _generationOwnerId == ownerId &&
        _generationFileName == fileName;

    if (sameRequest && _saved) return;

    setState(() {
      if (!sameRequest) {
        _resetGeneratedResult();

        _generationInput = reviewedText;
        _generationOwnerId = ownerId;
        _generationFileName = fileName;

        // Reuse this document ID when retrying a failed save.
        _summaryReference = FirebaseFirestore.instance
            .collection('summaries')
            .doc();
      }

      _busy = true;
      _error = null;
      _status = _summary == null
          ? 'Generating a summary from your reviewed text...'
          : 'Retrying summary save...';
    });

    try {
      _checkSession(ownerId);

      var generatedSummary = _summary;

      // Preserve the generated result if saving fails.
      // Retrying then only performs the Firestore write.
      if (generatedSummary == null) {
        final result = await OpenRouterService()
            .generateSummary(reviewedText);

        if (!mounted) return;

        _checkSession(ownerId);

        if (result.trim().isEmpty) {
          throw StateError(
            'The AI returned an empty summary. Please try again.',
          );
        }

        generatedSummary = result.trim();

        setState(() {
          _summary = generatedSummary;
        });
      }

      _checkSession(ownerId);

      setState(() {
        _status = 'Saving reviewed text and summary...';
      });

      final reference = _summaryReference!;

      await reference.set({
        'userId': ownerId,
        'fileName': fileName,
        'summary': generatedSummary,
        'reviewedText': reviewedText,
        'source': 'security_inspector',
        'textReviewed': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      _checkSession(ownerId);

      setState(() {
        _saved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reviewed text and summary saved to AI Summaries.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.code == 'permission-denied'
            ? 'Saving was denied. Check your verified login '
                'and Firestore rules, then tap Retry saving.'
            : 'Saving could not be confirmed. Check your '
                'connection and tap Retry saving.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error is StateError
            ? error.message.toString()
            : 'The request failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Widget _findingTile(SecurityFinding finding) {
    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            value: _selectedIds.contains(finding.id),
            title: Text(finding.title),
            subtitle: Text(
              '${finding.explanation}\n'
              'Position: ${finding.start + 1}–${finding.end}',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: _busy
                ? null
                : (selected) {
                    setState(() {
                      if (selected == true) {
                        _selectedIds.add(finding.id);
                      } else {
                        _selectedIds.remove(finding.id);
                      }

                      _previewReady = false;
                      _reviewed = false;
                      _previewController.clear();
                      _error = null;
                      _resetGeneratedResult();
                    });
                  },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _showMatch(finding),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Reveal match locally'),
            ),
          ),
        ],
      ),
    );
  }

  String get _actionLabel {
    if (_busy) return 'Processing...';
    if (_saved) return 'Saved to AI Summaries';
    if (_summary != null) return 'Retry saving';
    return 'Generate and save summary';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Security Inspector'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22223D),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.policy_outlined,
                        size: 42,
                        color: Color(0xFFB9F6D2),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Review before you share',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Inspect text locally, choose redactions, '
                        'then review the exact text used for your summary.',
                        style: TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'PDF, TXT, Markdown, CSV • Up to 10 MB\n'
                  'This is a text-pattern inspection tool, not an '
                  'antivirus. The original document is not modified.',
                  style: TextStyle(height: 1.5),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(
                    Icons.document_scanner_outlined,
                  ),
                  label: const Text('Select and inspect'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                  ),
                ),

                if (_busy) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                  if (_status.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(height: 1.5),
                    ),
                  ],
                ],

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: colors.onErrorContainer,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],

                if (report != null) ...[
                  const SizedBox(height: 24),
                  Text(
                    report.fileName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(report.formatCheck),
                  const SizedBox(height: 12),
                  const Text(
                    'SHA-256 fingerprint',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    report.fingerprint,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A fingerprint identifies these file bytes. '
                    'It does not establish trust or prove safety.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  for (final notice in report.notices)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('• $notice'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    report.findings.isEmpty
                        ? 'No configured text patterns matched'
                        : '${report.findings.length} possible findings',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Checked findings will be replaced with '
                    '[REDACTED]. Unchecking a finding may leave '
                    'its contents visible in the reviewed text.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  ...report.findings.map(_findingTile),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _buildPreview,
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Build redaction preview'),
                  ),
                ],

                if (_previewReady) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Review the text to summarize and save',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The text below will be sent to AI and saved '
                    'with its summary and filename in Firestore.\n\n'
                    'The original file, fingerprint, and detected '
                    'match values are not uploaded separately. '
                    'Any sensitive information left in this editor '
                    'will be included.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _previewController,
                    enabled: !_busy,
                    minLines: 8,
                    maxLines: 16,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Review and edit the text...',
                    ),
                    onChanged: (_) {
                      setState(() {
                        _reviewed = false;
                        _error = null;
                        _resetGeneratedResult();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'AI input limit: 20,000 characters. '
                    'Editing this text requires approval again. '
                    'Previously saved summaries remain available.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _reviewed,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'I approve sending this reviewed text to '
                      'OpenRouter and its selected AI provider, '
                      'and saving the reviewed text, summary, '
                      'and filename in Firestore.',
                    ),
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() {
                              _reviewed = value ?? false;
                            });
                          },
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy || !_reviewed || _saved
                        ? null
                        : _summarise,
                    icon: Icon(
                      _saved
                          ? Icons.check_circle_outline
                          : _summary != null
                              ? Icons.cloud_upload_outlined
                              : Icons.auto_awesome,
                    ),
                    label: Text(_actionLabel),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],

                if (_summary != null) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Icon(
                        _saved
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_upload_outlined,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Summary of reviewed text',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      _summary!,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _saved
                        ? 'Saved successfully. Open AI Summaries '
                            'from Home to view this result later.'
                        : _busy
                            ? 'Saving has not finished yet.'
                            : 'Saving has not been confirmed. '
                                'Tap Retry saving above.',
                    style: TextStyle(
                      color: _saved || _busy
                          ? colors.primary
                          : colors.error,
                      height: 1.5,
                    ),
                  ),
                  if (_saved && _summaryReference != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      'Summary ID: ${_summaryReference!.id}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Check the summary against your reviewed text. '
                    'AI can still make mistakes or add unsupported details.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}