import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'summary_detail_screen.dart';

class SummaryListScreen extends StatefulWidget {
  const SummaryListScreen({super.key});

  @override
  State<SummaryListScreen> createState() => _SummaryListScreenState();
}

class _SummaryListScreenState extends State<SummaryListScreen> {
  final _searchController = TextEditingController();

  StreamSubscription<User?>? _authSubscription;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _summariesStream;

  String? _ownerId;
  String _searchText = '';
  int _streamVersion = 0;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();

    _connectStream(FirebaseAuth.instance.currentUser?.uid);

    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted || user?.uid == _ownerId) return;

      setState(() {
        _searchController.clear();
        _searchText = '';
        _connectStream(user?.uid);
      });
    });
  }

  void _connectStream(String? uid) {
    _ownerId = uid;
    _streamVersion++;

    _summariesStream = uid == null
        ? null
        : FirebaseFirestore.instance
            .collection('summaries')
            .where('userId', isEqualTo: uid)
            .snapshots();
  }

  void _retry() {
    setState(() {
      _connectStream(FirebaseAuth.instance.currentUser?.uid);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _fileName(Map<String, dynamic> data) {
    final value = data['fileName'];

    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : 'Untitled summary';
  }

  String _summary(Map<String, dynamic> data) {
    final value = data['summary'];
    return value is String ? value : '';
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchText = '');
  }

  String _errorMessage(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Access was denied. Check your verified login '
            'and Firestore rules.';
      }

      if (error.code == 'unavailable') {
        return 'Check your internet connection and try again.';
      }
    }

    return 'Your summaries could not be loaded.';
  }

  void _openSummary(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    final data = document.data();

    if (user == null || data['userId'] != user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your session changed. Please sign in again.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SummaryDetailScreen(
          fileName: _fileName(data),
          summary: _summary(data),

          // Connect the details screen to the saved summary.
          summaryId: document.id,
          ownerId: user.uid,
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _primaryColor, size: 48),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
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
    final cardColor =
        isDark ? const Color(0xFF1C1C2C) : Colors.white;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: const Text(
          'AI Summaries',
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
        child: _summariesStream == null
            ? Center(
                child: _messagePanel(
                  icon: Icons.lock_outline_rounded,
                  title: 'Please log in',
                  message: 'Log in to view your saved summaries.',
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: CustomScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF8070EF),
                                      Color(0xFF5540C9),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(26),
                                ),
                                child: const Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    SizedBox(height: 18),
                                    Text(
                                      'Big ideas, made clearer.',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Read summaries, compare saved '
                                      'source text, and create quizzes '
                                      'and flashcards.',
                                      style: TextStyle(
                                        color: Colors.white,
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
                                    _searchText =
                                        value.trim().toLowerCase();
                                  });
                                },
                                decoration: InputDecoration(
                                  hintText: 'Search names or summary text...',
                                  prefixIcon:
                                      const Icon(Icons.search_rounded),
                                  suffixIcon:
                                      _searchController.text.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Clear search',
                                              onPressed: _clearSearch,
                                              icon: const Icon(Icons.close),
                                            ),
                                  filled: true,
                                  fillColor: cardColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        key: ValueKey(_streamVersion),
                        stream: _summariesStream,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.cloud_off_rounded,
                                title: 'Could not load summaries',
                                message: _errorMessage(snapshot.error),
                                action: TextButton.icon(
                                  onPressed: _retry,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try Again'),
                                ),
                              ),
                            );
                          }

                          if (!snapshot.hasData) {
                            return const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                            );
                          }

                          final all = snapshot.data!.docs;

                          if (all.isEmpty) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.auto_awesome_outlined,
                                title: 'No summaries yet',
                                message: 'Upload a document or save a '
                                    'summary through Security Inspector.',
                              ),
                            );
                          }

                          final filtered = all.where((document) {
                            final data = document.data();
                            return _fileName(data)
                                    .toLowerCase()
                                    .contains(_searchText) ||
                                _summary(data)
                                    .toLowerCase()
                                    .contains(_searchText);
                          }).toList();

                          if (filtered.isEmpty) {
                            return SliverToBoxAdapter(
                              child: _messagePanel(
                                icon: Icons.search_off_rounded,
                                title: 'No matching summaries',
                                message: 'Try another name or search word.',
                                action: TextButton(
                                  onPressed: _clearSearch,
                                  child: const Text('Clear search'),
                                ),
                              ),
                            );
                          }

                          return SliverPadding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index == 0) {
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Text(
                                        '${filtered.length} '
                                        '${filtered.length == 1 ? 'summary' : 'summaries'}',
                                        style: TextStyle(
                                          color: secondaryColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    );
                                  }

                                  final document = filtered[index - 1];
                                  final data = document.data();
                                  final summary = _summary(data);

                                  return Padding(
                                    key: ValueKey(document.id),
                                    padding:
                                        const EdgeInsets.only(bottom: 14),
                                    child: Material(
                                      color: cardColor,
                                      borderRadius:
                                          BorderRadius.circular(22),
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: () => _openSummary(document),
                                        child: Padding(
                                          padding: const EdgeInsets.all(20),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.auto_awesome,
                                                    color: _primaryColor,
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      _fileName(data),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: textColor,
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right,
                                                    color: secondaryColor,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                summary.trim().isEmpty
                                                    ? 'No summary text available.'
                                                    : summary.trim(),
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: secondaryColor,
                                                  height: 1.6,
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              const Text(
                                                'Read summary',
                                                style: TextStyle(
                                                  color: _primaryColor,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                childCount: filtered.length + 1,
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
}