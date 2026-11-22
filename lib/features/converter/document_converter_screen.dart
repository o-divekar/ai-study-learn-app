import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../pdf/pdf_viewer_screen.dart';
import 'converted_file_viewer_screen.dart';
import '../../core/services/document_converter_service.dart';
import 'package:share_plus/share_plus.dart';

class DocumentConverterScreen extends StatefulWidget {
  const DocumentConverterScreen({super.key});

  @override
  State<DocumentConverterScreen> createState() =>
      _DocumentConverterScreenState();
}

class _DocumentConverterScreenState
    extends State<DocumentConverterScreen> {
  final _service = DocumentConverterService();

  ConversionType _type = ConversionType.pdfToWord;

  String? _inputPath;
  String? _inputName;
  File? _output;

  bool _busy = false;
  String _status = 'Choose a conversion and select a document.';
  String? _error;

  static const _purple = Color(0xFF6750E8);

  String _message(Object error) {
    if (error is StateError) return error.message.toString();

    return 'The operation failed. Check that the file is readable, '
        'not password-protected, and uses the selected format.';
  }



  Future<void> _shareFile(BuildContext buttonContext) async {
  final output = _output;

  if (output == null || _busy) return;

  // Capture the button position before awaiting.
  // This also supplies the share-menu anchor required on iPad.
  final renderObject = buttonContext.findRenderObject();

  final Rect? origin =
      renderObject is RenderBox && renderObject.hasSize
          ? renderObject.localToGlobal(Offset.zero) & renderObject.size
          : null;

  setState(() {
    _busy = true;
    _error = null;
  });

  try {
    if (!await output.exists()) {
      throw StateError(
        'The converted file is no longer available. Convert it again.',
      );
    }

    final fileName =
        output.path.replaceAll('\\', '/').split('/').last;

    final extension = fileName.split('.').last.toLowerCase();

    final String mimeType;

    switch (extension) {
      case 'pdf':
        mimeType = 'application/pdf';
        break;
      case 'docx':
        mimeType =
            'application/vnd.openxmlformats-officedocument.'
            'wordprocessingml.document';
        break;
      case 'xlsx':
        mimeType =
            'application/vnd.openxmlformats-officedocument.'
            'spreadsheetml.sheet';
        break;
      default:
        mimeType = 'application/octet-stream';
    }

    if (!mounted) return;

    await SharePlus.instance.share(
      ShareParams(
        title: 'Share converted document',
        subject: fileName,
        files: [
          XFile(
            output.path,
            mimeType: mimeType,
          ),
        ],
        sharePositionOrigin: origin,
      ),
    );

    // Do not claim delivery: the receiving app controls sending.
  } catch (error) {
    if (!mounted) return;

    setState(() {
      _error = error is StateError
          ? error.message.toString()
          : 'Could not open the sharing menu. Please try again.';
    });
  } finally {
    if (mounted) {
      setState(() => _busy = false);
    }
  }
}

  Future<void> _pick() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [_type.inputExtension],
        allowMultiple: false,
      );

      if (!mounted || result == null) return;

      final selected = result.files.single;

      if (selected.path == null) {
        throw StateError('The selected file could not be accessed.');
      }

      setState(() {
        _inputPath = selected.path;
        _inputName = selected.name;
        _output = null;
        _status = 'Ready to convert.';
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  

  Future<void> _convert() async {
    if (_busy || _inputPath == null || _inputName == null) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() => _error = 'Please sign in again.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _output = null;
      _status = 'Converting your document...';
    });

    try {
      // Let the loading indicator paint before processing starts.
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final output = await _service.convert(
        path: _inputPath!,
        fileName: _inputName!,
        type: _type,
        ownerId: user.uid,
      );

      if (!mounted) return;

      if (FirebaseAuth.instance.currentUser?.uid != user.uid) {
        throw StateError('Your session changed. Please sign in again.');
      }

      setState(() {
        _output = output;
        _status = 'Conversion complete. Open the result or save a copy.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _message(error);
          _status = 'Conversion could not finish.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
  final output = _output;

  if (output == null || _busy) return;

  try {
    if (!await output.exists()) {
      throw StateError(
        'The converted file is no longer available. Convert it again.',
      );
    }

    if (!mounted) return;

    final isPdf = output.path.toLowerCase().endsWith('.pdf');

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isPdf
            ? PdfViewerScreen(pdfPath: output.path)
            : ConvertedFileViewerScreen(filePath: output.path),
      ),
    );
  } catch (error) {
    if (!mounted) return;

    setState(() {
      _error = _message(error);
    });
  }
}

  Future<void> _saveCopy() async {
    final output = _output;
    if (output == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final bytes = await output.readAsBytes();

      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save converted document',
        fileName: output.path.split(Platform.pathSeparator).last,
        type: FileType.custom,
        allowedExtensions: [_type.outputExtension],
        bytes: Uint8List.fromList(bytes),
      );

      if (!mounted || destination == null) return;

      setState(() {
        _status = 'Your converted document was exported.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Converter'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _purple,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.transform,
                          color: Colors.white,
                          size: 40,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Convert your study documents',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Files are processed on this device.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<ConversionType>(
                    value: _type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Conversion',
                      border: OutlineInputBorder(),
                    ),
                    items: ConversionType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      );
                    }).toList(),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;

                            setState(() {
                              _type = value;
                              _inputPath = null;
                              _inputName = null;
                              _output = null;
                              _error = null;
                              _status = 'Select a document.';
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _type.description,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'PDF creation currently supports English text. '
                    'Maximum input file size: 10 MB.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      'Select ${_type.inputExtension.toUpperCase()}',
                    ),
                  ),
                  if (_inputName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _inputName!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _busy || _inputPath == null ? null : _convert,
                    icon: const Icon(Icons.transform),
                    label: const Text('Convert'),
                  ),
                  const SizedBox(height: 20),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  Text(_status),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (_output != null) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _open,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Open converted file'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _saveCopy,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Save a copy'),
                    ),

                    const SizedBox(height: 8),
                    Builder(
                      builder: (buttonContext) {
                        return OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _shareFile(buttonContext),
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Share file'),
                        );
                      },
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