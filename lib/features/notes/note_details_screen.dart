import 'package:flutter/material.dart';

import '../../models/note_model.dart';
import '../../repositories/notes_repository.dart';

class NoteDetailsScreen extends StatefulWidget {
  final NoteModel note;

  const NoteDetailsScreen({
    super.key,
    required this.note,
  });

  @override
  State<NoteDetailsScreen> createState() => _NoteDetailsScreenState();
}

class _NoteDetailsScreenState extends State<NoteDetailsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController titleController;
  late final TextEditingController contentController;

  final NotesRepository repository = NotesRepository();

  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isBusy => _isSaving || _isDeleting;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();

    titleController = TextEditingController(
      text: widget.note.title,
    );

    contentController = TextEditingController(
      text: widget.note.content,
    );
  }

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> updateNote() async {
    if (_isBusy || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedNote = NoteModel(
        id: widget.note.id,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        userId: widget.note.userId,
      );

      await repository.updateNote(updatedNote);

      if (!mounted) return;

      _showMessage('Note updated successfully.');
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Updating note failed: $e');

      _showMessage(
        'Could not update your note. Your edits are still here. '
        'Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> deleteNote() async {
    if (_isBusy) return;

    FocusScope.of(context).unfocus();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete this note?'),
          content: Text(
            '“${widget.note.title}” will be permanently deleted. '
            'This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(dialogContext).colorScheme.error,
                foregroundColor:
                    Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted || _isBusy) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await repository.deleteNote(widget.note.id);

      if (!mounted) return;

      _showMessage('Note deleted.');
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Deleting note failed: $e');

      _showMessage('Could not delete this note. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    IconData? icon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      prefixIcon: icon == null ? null : Icon(icon, size: 22),
      filled: true,
      fillColor:
          isDark ? const Color(0xFF252536) : const Color(0xFFF7F8FC),
      contentPadding: const EdgeInsets.all(18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark
              ? const Color(0xFF39394F)
              : const Color(0xFFE5E7F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: _primaryColor,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.error,
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);

    final secondaryColor =
        isDark ? const Color(0xFFB3B5C9) : const Color(0xFF74788D);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'Edit Note',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (_isDeleting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _primaryColor,
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Delete note',
              onPressed: _isBusy ? null : deleteNote,
              icon: const Icon(Icons.delete_outline_rounded),
              color: Theme.of(context).colorScheme.error,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF11111D),
                    const Color(0xFF1B1730),
                  ]
                : [
                    const Color(0xFFF5F5FF),
                    const Color(0xFFEDF5FF),
                    const Color(0xFFFFF7FC),
                  ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF8B74FF),
                                _primaryColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.edit_document,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Build on your ideas',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Refine your explanation, add examples, '
                        'or update what you have learned.',
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1C1C2C)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF303044)
                                : const Color(0xFFECECF6),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(
                                isDark ? 25 : 8,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Note details',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 22),
                            TextFormField(
                              controller: titleController,
                              enabled: !_isBusy,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(
                                label: 'Title',
                                hint: 'Give your note a clear title',
                                icon: Icons.title_rounded,
                              ),
                              validator: (value) {
                                if (value == null ||
                                    value.trim().isEmpty) {
                                  return 'Please enter a title';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
                              controller: contentController,
                              enabled: !_isBusy,
                              minLines: 8,
                              maxLines: 18,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 15,
                                height: 1.6,
                              ),
                              decoration: _inputDecoration(
                                label: 'Content',
                                hint: 'Write your notes here...',
                              ),
                              validator: (value) {
                                if (value == null ||
                                    value.trim().isEmpty) {
                                  return 'Please write some content';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            ValueListenableBuilder<TextEditingValue>(
                              valueListenable: contentController,
                              builder: (context, value, child) {
                                final text = value.text.trim();

                                final words = text.isEmpty
                                    ? 0
                                    : text.split(RegExp(r'\s+')).length;

                                return Text(
                                  '$words ${words == 1 ? 'word' : 'words'}',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: secondaryColor,
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 26),
                            ElevatedButton.icon(
                              onPressed: _isBusy ? null : updateNote,
                              icon: _isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.save_outlined,
                                      size: 21,
                                    ),
                              label: Text(
                                _isSaving ? 'Updating...' : 'Update Note',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    _primaryColor.withAlpha(150),
                                disabledForegroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                elevation: 0,
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Changes are saved when you tap Update Note.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}