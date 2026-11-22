import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<List<int>> _statsFuture;

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();
    _statsFuture = _loadStats();
  }

  Future<List<int>> _loadStats() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('Please log in to view your dashboard.');
    }

    final collections = [
      'pdf_notes',
      'summaries',
      'quizzes',
      'flashcards',
    ];

    return Future.wait(
      collections.map((collection) async {
        final snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .where('userId', isEqualTo: user.uid)
            .get();

        return snapshot.docs.length;
      }),
    );
  }

  Future<void> _refresh() async {
    final future = _loadStats();

    setState(() {
      _statsFuture = future;
    });

    try {
      await future;
    } catch (_) {
      // FutureBuilder displays the error and retry action.
    }
  }

  String _errorMessage(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Access was denied. Make sure your email is verified '
            'and your Firestore rules allow your account '
            'to read its own study records.';
      }

      if (error.code == 'unavailable') {
        return 'Unable to connect. Check your internet connection '
            'and try again.';
      }
    }

    if (error is StateError) {
      return error.message.toString();
    }

    return 'Your statistics could not be loaded. Please try again.';
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
          'Dashboard',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<List<int>>(
          future: _statsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  color: _primaryColor,
                ),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 56,
                        color: _primaryColor,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Could not load dashboard',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _errorMessage(snapshot.error),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: secondaryColor,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Try Again'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            final counts = snapshot.data!;

            final stats = [
              _DashboardStat(
                title: 'PDFs Uploaded',
                subtitle: 'Your study documents',
                count: counts[0],
                icon: Icons.picture_as_pdf_rounded,
                color: const Color(0xFFE76D78),
              ),
              _DashboardStat(
                title: 'Summaries',
                subtitle: 'Key ideas, simplified',
                count: counts[1],
                icon: Icons.auto_awesome_rounded,
                color: _primaryColor,
              ),
              _DashboardStat(
                title: 'Quizzes',
                subtitle: 'Practice your knowledge',
                count: counts[2],
                icon: Icons.quiz_rounded,
                color: const Color(0xFF2785D5),
              ),
              _DashboardStat(
                title: 'Flashcards',
                subtitle: 'Saved revision sets',
                count: counts[3],
                icon: Icons.style_rounded,
                color: const Color(0xFF209C86),
              ),
            ];

            final isEmpty = counts.every((count) => count == 0);

            return RefreshIndicator(
              color: _primaryColor,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: [
                                BoxShadow(
                                  color: _primaryColor.withAlpha(45),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(35),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Icon(
                                    Icons.auto_stories_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'Your learning overview',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  isEmpty
                                      ? 'Start with a PDF and build your '
                                          'personal study collection.'
                                      : 'Your documents and study tools, '
                                          'together in one place.',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(220),
                                    fontSize: 15,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          Text(
                            'My study collection',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'A snapshot of your saved study material.',
                            style: TextStyle(
                              color: secondaryColor,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final textScale =
                                  MediaQuery.textScalerOf(context).scale(1);

                              final columns = textScale > 1.3
                                  ? 1
                                  : constraints.maxWidth >= 850
                                      ? 4
                                      : constraints.maxWidth >= 340
                                          ? 2
                                          : 1;

                              const spacing = 16.0;

                              final cardWidth =
                                  (constraints.maxWidth -
                                          spacing * (columns - 1)) /
                                      columns;

                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: stats.map((stat) {
                                  return SizedBox(
                                    width: cardWidth,
                                    child: _buildStatCard(
                                      stat: stat,
                                      isDark: isDark,
                                      textColor: textColor,
                                      secondaryColor: secondaryColor,
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1C1C2C)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.lightbulb_outline_rounded,
                                  color: _primaryColor,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    isEmpty
                                        ? 'Upload your first PDF from Home '
                                            'to get started.'
                                        : 'Try a quiz after reading a summary '
                                            'to check what you remember.',
                                    style: TextStyle(
                                      color: secondaryColor,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Pull down to refresh',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryColor,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required _DashboardStat stat,
    required bool isDark,
    required Color textColor,
    required Color secondaryColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2C) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? const Color(0xFF303044)
              : const Color(0xFFECECF6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 20 : 7),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: stat.color.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              stat.icon,
              color: stat.color,
              size: 26,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            stat.count.toString(),
            style: TextStyle(
              color: textColor,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            stat.title,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stat.subtitle,
            style: TextStyle(
              color: secondaryColor,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardStat {
  final String title;
  final String subtitle;
  final int count;
  final IconData icon;
  final Color color;

  const _DashboardStat({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.icon,
    required this.color,
  });
}