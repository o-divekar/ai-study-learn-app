import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/note_model.dart';
import '../../repositories/notes_repository.dart';

class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({super.key});

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final _formKey = GlobalKey<FormState>();

  final titleController = TextEditingController();
  final contentController = TextEditingController();

  final NotesRepository repository = NotesRepository();

  bool _isSaving = false;

  static const _primaryColor = Color(0xFF6750E8);

  Future<void> saveNote() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('Please log in before saving a note.');
      return;
    }

    if (!user.emailVerified) {
      _showMessage('Please verify your email before saving a note.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final note = NoteModel(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        userId: user.uid,
      );

      await repository.createNote(note);

      if (!mounted) return;

      _showMessage('Note saved successfully.');
      Navigator.of(context).pop(true);
    } on FirebaseException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'permission-denied':
          _showMessage(
            'You do not have permission to save this note. '
            'Check your email verification and Firestore rules.',
          );
          break;
        case 'unavailable':
          _showMessage(
            'Unable to connect. Check your internet connection '
            'and try again.',
          );
          break;
        default:
          _showMessage('Could not save your note. Please try again.');
      }
    } catch (e) {
      debugPrint('Saving note failed: $e');
      _showMessage('Could not save your note. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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

  @override
  void dispose() {
    titleController.dispose();
    contentController.dispose();
    super.dispose();
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
          'Create Note',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
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
                            Icons.edit_note_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Capture your next idea',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Keep your explanations, key points, and '
                        'study reminders together.',
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
                              enabled: !_isSaving,
                              textCapitalization:
                                  TextCapitalization.sentences,
                              textInputAction: TextInputAction.next,
                              maxLength: 120,
                              decoration: _inputDecoration(
                                label: 'Title',
                                hint: 'e.g. Understanding neural networks',
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
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: contentController,
                              enabled: !_isSaving,
                              minLines: 8,
                              maxLines: 16,
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
                                hint: 'Start writing here...\n\n'
                                    'Add definitions, examples, '
                                    'or points you want to remember.',
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
                              onPressed: _isSaving ? null : saveNote,
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
                                _isSaving ? 'Saving...' : 'Save Note',
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
                        'Tap Save Note before leaving this screen.',
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