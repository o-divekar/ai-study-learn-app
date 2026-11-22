import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/session_manager.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int totalPdfs = 0;
  int totalSummaries = 0;
  int totalQuizzes = 0;

  bool isLoading = true;
  bool _isLoggingOut = false;

  String? _error;
  String _name = 'Your Profile';

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();
    loadStats();
  }

  Future<void> loadStats() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        _error = 'Your session has ended. Please log in again.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      _error = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      // Start the profile and statistics requests together.
      final results = await Future.wait<Object>([
        firestore.collection('users').doc(user.uid).get(),
        firestore
            .collection('pdf_notes')
            .where('userId', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('summaries')
            .where('userId', isEqualTo: user.uid)
            .get(),
        firestore
            .collection('quizzes')
            .where('userId', isEqualTo: user.uid)
            .get(),
      ]);

      if (!mounted ||
          FirebaseAuth.instance.currentUser?.uid != user.uid) {
        return;
      }

      final profile =
          results[0] as DocumentSnapshot<Map<String, dynamic>>;

      final pdfs =
          results[1] as QuerySnapshot<Map<String, dynamic>>;

      final summaries =
          results[2] as QuerySnapshot<Map<String, dynamic>>;

      final quizzes =
          results[3] as QuerySnapshot<Map<String, dynamic>>;

      final storedName = profile.data()?['name'];
      final firebaseName = user.displayName?.trim();

      setState(() {
        _name = storedName is String && storedName.trim().isNotEmpty
            ? storedName.trim()
            : firebaseName != null && firebaseName.isNotEmpty
                ? firebaseName
                : 'Your Profile';

        totalPdfs = pdfs.docs.length;
        totalSummaries = summaries.docs.length;
        totalQuizzes = quizzes.docs.length;
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.code == 'permission-denied'
            ? 'Access was denied. Check your email verification '
                'and Firestore rules.'
            : 'Your profile could not be loaded. '
                'Check your connection and try again.';
      });
    } catch (e) {
      debugPrint('Loading profile failed: $e');

      if (!mounted) return;

      setState(() {
        _error = 'Your profile could not be loaded. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> logout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await SessionManager.instance.signOut();

      // main.dart returns to Login and clears the previous routes.
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
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
          'Profile',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: textColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh profile',
            onPressed:
                isLoading || _isLoggingOut ? null : loadStats,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: _primaryColor,
                ),
              )
            : RefreshIndicator(
                onRefresh: loadStats,
                color: _primaryColor,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(26),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF8070EF),
                                    Color(0xFF5540C9),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(28),
                                boxShadow: [
                                  BoxShadow(
                                    color: _primaryColor.withAlpha(40),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withAlpha(90),
                                        width: 2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 43,
                                      backgroundColor:
                                          Colors.white.withAlpha(35),
                                      child: const Icon(
                                        Icons.person_rounded,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Text(
                                    _name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Your personal study space',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1C1C2C)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Account details',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.mail_outline_rounded,
                                        color: _primaryColor,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Email',
                                              style: TextStyle(
                                                color: secondaryColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            SelectableText(
                                              user?.email ??
                                                  'Not available',
                                              style: TextStyle(
                                                color: textColor,
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    children: [
                                      Icon(
                                        user?.emailVerified == true
                                            ? Icons.verified_rounded
                                            : Icons.info_outline_rounded,
                                        color: user?.emailVerified == true
                                            ? const Color(0xFF209C86)
                                            : secondaryColor,
                                        size: 21,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          user?.emailVerified == true
                                              ? 'Email verified'
                                              : 'Email not verified',
                                          style: TextStyle(
                                            color: secondaryColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 26),
                            Text(
                              'Your study activity',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1C1C2C)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(
                                      Icons.cloud_off_rounded,
                                      color: _primaryColor,
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: secondaryColor,
                                        height: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: loadStats,
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                      ),
                                      label: const Text('Try Again'),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              _statCard(
                                title: 'Total PDFs',
                                count: totalPdfs,
                                icon: Icons.picture_as_pdf_rounded,
                                color: const Color(0xFFE76D78),
                              ),
                              const SizedBox(height: 12),
                              _statCard(
                                title: 'Total Summaries',
                                count: totalSummaries,
                                icon: Icons.description_rounded,
                                color: _primaryColor,
                              ),
                              const SizedBox(height: 12),
                              _statCard(
                                title: 'Total Quizzes',
                                count: totalQuizzes,
                                icon: Icons.quiz_rounded,
                                color: const Color(0xFF2785D5),
                              ),
                            ],
                            const SizedBox(height: 30),
                            ElevatedButton.icon(
                              onPressed: _isLoggingOut ? null : logout,
                              icon: _isLoggingOut
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.logout_rounded),
                              label: Text(
                                _isLoggingOut ? 'Logging out...' : 'Logout',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
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
                            const SizedBox(height: 16),
                            Text(
                              'Signing out ends your current session.',
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
              ),
      ),
    );
  }

  Widget _statCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C2C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? const Color(0xFF303044)
              : const Color(0xFFECECF6),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 25),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : const Color(0xFF202238),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}