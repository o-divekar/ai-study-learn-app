import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'ask_pdf_screen.dart';
import 'pdf_viewer_screen.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';

import '../../core/services/document_text_service.dart';


class MyPdfsScreen extends StatefulWidget {
  const MyPdfsScreen({super.key});

  @override
  State<MyPdfsScreen> createState() => _MyPdfsScreenState();
}

class _MyPdfsScreenState extends State<MyPdfsScreen> {
  final _searchController = TextEditingController();
  final Set<String> _deletingIds = {};
  Stream<QuerySnapshot<Map<String, dynamic>>>? _pdfStream;
  String _searchQuery = '';

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      _pdfStream = FirebaseFirestore.instance
          .collection('pdf_notes')
          .where('userId', isEqualTo: user.uid)
          .snapshots();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _askPdf(
  QueryDocumentSnapshot<Map<String, dynamic>> document,
) {
  final data = document.data();
  final user = FirebaseAuth.instance.currentUser;

  if (user == null ||
      !user.emailVerified ||
      data['userId'] != user.uid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please sign in with your verified account.'),
      ),
    );
    return;
  }

  if (data['extractionStatus'] != 'ready' ||
      data['textStorage'] != 'pages') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This PDF needs page extraction. Finish processing it '
          'or upload it again using the updated upload screen.',
        ),
      ),
    );
    return;
  }

  FocusScope.of(context).unfocus();

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AskPdfScreen(
      pdfId: document.id,
      fileName: _fileName(data),
      ownerId: user.uid,
      pdfPath: _pdfPath(data),
    ),
    ),
  );
}

  String _fileName(Map<String, dynamic> data) {
    final value = data['fileName'];

    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }

    return 'Untitled PDF';
  }

  String _pdfPath(Map<String, dynamic> data) {
    final value = data['pdfPath'];
    return value is String ? value.trim() : '';
  }

  String? _createdDate(Map<String, dynamic> data) {
    final value = data['createdAt'];

    if (value is! Timestamp) return null;

    final date = value.toDate().toLocal();

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
    });
  }

 Future<void> _deletePdf(
  QueryDocumentSnapshot<Map<String, dynamic>> document,
) async {
  if (_deletingIds.contains(document.id)) return;

  final user = FirebaseAuth.instance.currentUser;
  final data = document.data();

  if (user == null ||
      !user.emailVerified ||
      data['userId'] != user.uid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Please sign in with your verified account '
          'to delete your own PDFs.',
        ),
      ),
    );
    return;
  }

  // Prevent repeated taps, including while confirmation is open.
  setState(() {
    _deletingIds.add(document.id);
  });

  void checkSession() {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null ||
        currentUser.uid != user.uid ||
        !currentUser.emailVerified) {
      throw StateError(
        'Your session changed. Please sign in again.',
      );
    }
  }

  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete PDF?'),
          content: Text(
            'Remove "${_fileName(data)}", its extracted pages, '
            'and its question history?\n\n'
            'Its summaries, quizzes, flashcards, and local PDF file '
            'will remain.',
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
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    checkSession();

    // Keep the parent document until its children are deleted.
    // The subcollection rules use it to check ownership.
    await document.reference.update({
      'extractionStatus': 'deleting',
    });

    // Delete extracted pages, then saved question history.
    for (final collectionName in ['pages', 'chat_history']) {
      while (true) {
        checkSession();

        final children = await document.reference
            .collection(collectionName)
            .limit(10)
            .get(const GetOptions(source: Source.server));

        if (children.docs.isEmpty) break;

        checkSession();

        final batch = FirebaseFirestore.instance.batch();

        for (final child in children.docs) {
          batch.delete(child.reference);
        }

        await batch.commit();
      }
    }

    // Delete the parent LAST.
    checkSession();
    await document.reference.delete();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'PDF record, extracted pages, and question history deleted.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (error) {
    if (!mounted) return;

    String message;

    if (error is StateError) {
      message = error.message.toString();
    } else if (error is FirebaseException &&
        error.code == 'permission-denied') {
      message = 'Deletion was denied. Check your verified login '
          'and the rules for PDF pages and chat history.';
    } else {
      message = 'Deletion could not finish. '
          'Check your connection and tap Delete again to retry.';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        _deletingIds.remove(document.id);
      });
    }
  }
}

  Future<void> _openPdf(Map<String, dynamic> data) async {
        final storedPath = data['localPath'];

        final path = storedPath is String && storedPath.trim().isNotEmpty
            ? storedPath
            : _pdfPath(data);

        final fileType = DocumentTextService.extension(_fileName(data));

        if (path.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No local file path is saved for this document.'),
            ),
          );
          return;
        }

        try {
          if (!await File(path).exists()) {
            throw StateError(
              'This document is not available on this device. '
              'Select the original file again through Upload Document.',
            );
          }

          if (!mounted) return;

          FocusScope.of(context).unfocus();

          if (fileType == 'pdf') {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PdfViewerScreen(pdfPath: path),
              ),
            );
            return;
          }

          final result = await OpenFilex.open(path);

          if (!mounted) return;

          if (result.type != ResultType.done) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not open this document. '
                  'Check that a compatible viewer is installed.\n'
                  '${result.message}',
                ),
              ),
            );
          }
        } catch (error) {
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is StateError
                    ? error.message.toString()
                    : 'The document could not be opened.',
              ),
            ),
          );
        }
      }

  String _errorMessage(Object? error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'Access was denied. Check your email verification '
              'and the Firestore rules for your PDF records.';
        case 'unavailable':
          return 'Unable to connect. Please check your internet '
              'connection and reopen this screen.';
      }
    }
    return 'Your PDF list could not be loaded. '
        'Please try reopening this screen.';
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
          'My PDFs',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: _pdfStream == null
            ? _messagePanel(
                icon: Icons.lock_outline_rounded,
                title: 'Please log in',
                message: 'Log in to view your saved PDF records.',
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: CustomScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          0,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF8070EF),
                                      Color(0xFF5540C9),
                                    ],
                                  ),
                                  borderRadius:
                                      BorderRadius.circular(26),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withAlpha(35),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: const Icon(
                                        Icons.folder_copy_outlined,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Your reading collection',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Find your study documents '
                                      'and pick up where you left off.',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(220),
                                        fontSize: 14,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  setState(() {
                                    _searchQuery =
                                        value.trim().toLowerCase();
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search PDF names...',
                                  prefixIcon:
                                      const Icon(Icons.search_rounded),
                                  suffixIcon:
                                      _searchController.text.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Clear search',
                                              onPressed: _clearSearch,
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                            ),
                                  filled: true,
                                  fillColor: isDark
                                      ? const Color(0xFF1C1C2C)
                                      : Colors.white,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 16,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                    borderSide: const BorderSide(
                                      color: _primaryColor,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                      StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>>(
                        stream: _pdfStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.cloud_off_rounded,
                                title: 'Could not load PDFs',
                                message: _errorMessage(snapshot.error),
                              ),
                            );
                          }

                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              !snapshot.hasData) {
                            return const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _primaryColor,
                                  ),
                                ),
                              ),
                            );
                          }

                          final allDocs = snapshot.data?.docs ?? [];

                          if (allDocs.isEmpty) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.picture_as_pdf_outlined,
                                title: 'No PDFs yet',
                                message: 'Use Upload PDF on your Home '
                                    'screen to add your first document.',
                              ),
                            );
                          }

                          final docs = allDocs.where((doc) {
                            return _fileName(doc.data())
                                .toLowerCase()
                                .contains(_searchQuery);
                          }).toList();

                          if (docs.isEmpty) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.search_off_rounded,
                                title: 'No matching PDFs',
                                message: 'Try another filename.',
                                action: TextButton(
                                  onPressed: _clearSearch,
                                  child: const Text('Clear search'),
                                ),
                              ),
                            );
                          }

                          return SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 16,
                                      ),
                                      child: Text(
                                        _searchQuery.isEmpty
                                            ? '${docs.length} saved '
                                                '${docs.length == 1 ? 'PDF' : 'PDFs'}'
                                            : '${docs.length} '
                                                '${docs.length == 1 ? 'result' : 'results'}',
                                        style: TextStyle(
                                          color: secondaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }

                                  final doc = docs[index - 1];
                                  final data = doc.data();
                                  final hasPath =
                                      _pdfPath(data).isNotEmpty;
                                  final date = _createdDate(data);

                                  return Padding(
                                    key: ValueKey(doc.id),
                                    padding: const EdgeInsets.only(
                                      bottom: 12,
                                    ),
                                    child: Material(
                                      color: isDark
                                          ? const Color(0xFF1C1C2C)
                                          : Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: _deletingIds.contains(doc.id)
                                        ? null
                                        : () => _openPdf(data),
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.all(18),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(
                                                  12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFE76D78,
                                                  ).withAlpha(25),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                    14,
                                                  ),
                                                ),
                                                child: const Icon(
                                                  Icons
                                                      .picture_as_pdf_rounded,
                                                  color:
                                                      Color(0xFFE76D78),
                                                  size: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .start,
                                                  children: [
                                                    Text(
                                                      _fileName(data),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow
                                                              .ellipsis,
                                                      style: TextStyle(
                                                        color: textColor,
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(
                                                      height: 6,
                                                    ),
                                                    Text(
                                                      hasPath
                                                          ? 'Tap to open'
                                                          : 'File path missing',
                                                      style: TextStyle(
                                                        color:
                                                            secondaryColor,
                                                        fontSize: 12,
                                                      ),
                                                      
                                                    ),
                                                    if (date != null) ...[
                                                      const SizedBox(
                                                        height: 4,
                                                      ),
                                                      Text(
                                                        'Added $date',
                                                        style: TextStyle(
                                                          color:
                                                              secondaryColor,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 8),
                                                    if (DocumentTextService.extension(_fileName(data)) == 'pdf')
                                                    TextButton.icon(
                                                      onPressed: _deletingIds.contains(doc.id)
                                                          ? null
                                                          : () => _askPdf(doc),
                                                      icon: const Icon(Icons.auto_awesome, size: 18),
                                                      label: const Text('Ask Document'),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              if (_deletingIds.contains(doc.id))
                                            const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              ),
                                            )
                                          else
                                            IconButton(
                                              tooltip: 'Delete document',
                                              icon: const Icon(Icons.delete_outline_rounded),
                                              color: Theme.of(context).colorScheme.error,
                                              onPressed: () => _deletePdf(doc),
                                            ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                childCount: docs.length + 1,
                              ),
                            ),
                          );
                        },
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 28),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _messagePanel({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: _primaryColor),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF202238),
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? const Color(0xFFB3B5C9)
                  : const Color(0xFF74788D),
              height: 1.5,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}