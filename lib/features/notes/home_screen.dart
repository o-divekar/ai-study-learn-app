import 'package:ai_study_notes/features/ai/summary_list_screen.dart';
import 'package:ai_study_notes/features/auth/session_manager.dart';
import 'package:ai_study_notes/features/dashboard/dashboard_screen.dart';
import 'package:ai_study_notes/features/pdf/my_pdfs_screen.dart';
import 'package:ai_study_notes/features/profile/profile_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../converter/document_converter_screen.dart';
import '../../models/note_model.dart';
import '../../repositories/notes_repository.dart';
import '../../widgets/note_card.dart';
import '../ai/saved_activities_screen.dart';
import '../pdf/upload_pdf_screen.dart';
import 'create_notes_screen.dart';
import '../games/packet_rescue_screen.dart';
import '../security/document_security_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = NotesRepository();
  final _searchController = TextEditingController();

  late final Stream<List<NoteModel>> _notesStream;

  String _searchQuery = '';

  static const _primaryColor = Color(0xFF6750E8);

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    _notesStream = user == null
        ? Stream<List<NoteModel>>.value([])
        : _repository.getNotes(user.uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openScreen(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _clearSearch() {
    _searchController.clear();

    setState(() {
      _searchQuery = '';
    });
  }

  String _notesError(Object? error) {
    if (error is FirebaseException &&
        error.code == 'permission-denied') {
      return 'Access to your notes was denied. Check your email '
          'verification and the notes collection rules.';
    }

    return 'Your notes could not be loaded. '
        'Check your connection and try reopening this screen.';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor =
        isDark ? Colors.white : const Color(0xFF202238);

    final secondaryColor =
        isDark ? const Color(0xFFB3B5C9) : const Color(0xFF74788D);

    if (user == null) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              await SessionManager.instance.signOut();
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    final displayName = user.displayName?.trim();
    final greeting = displayName != null && displayName.isNotEmpty
        ? 'Hello, ${displayName.split(RegExp(r'\s+')).first}'
        : 'Welcome back';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
      appBar: AppBar(
        title: Text(
          'My Notes',
          style: TextStyle(
            color: textColor,
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
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => _openScreen(const ProfileScreen()),
          ),
            IconButton(
            tooltip: 'Saved quizzes and flashcards',
            icon: const Icon(Icons.school_outlined),
            onPressed: () {
              _openScreen(const SavedActivitiesScreen());
            },
          ),
          IconButton(
          tooltip: 'Play Packet Rescue',
          icon: const Icon(Icons.sports_esports_outlined),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PacketRescueScreen(),
              ),
            );
          },
        ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              // main.dart handles navigation and clears old routes.
              await SessionManager.instance.signOut();
            },
          ),

          IconButton(
          tooltip: 'Document Converter',
          icon: const Icon(Icons.transform),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const DocumentConverterScreen(),
              ),
            );
          },
        ),

          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
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
                                color: _primaryColor.withAlpha(40),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                greeting,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(220),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Make room for\n'
                                'your next idea.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 29,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Keep your notes, PDFs, and summaries '
                                'together as you learn.',
                                style: TextStyle(
                                  color: Colors.white.withAlpha(220),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () {
                                  _openScreen(const UploadPdfScreen());
                                },
                                icon: const Icon(
                                  Icons.upload_file_rounded,
                                  size: 20,
                                ),
                                label: const Text('Upload PDF'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: _primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Your study tools',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final largeText =
                                MediaQuery.textScalerOf(context)
                                        .scale(1) >
                                    1.3;

                            final columns = largeText
                                ? 1
                                : constraints.maxWidth >= 650
                                    ? 3
                                    : constraints.maxWidth >= 340
                                        ? 2
                                        : 1;

                            const spacing = 12.0;

                            final width = (constraints.maxWidth -
                                    spacing * (columns - 1)) /
                                columns;

                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: [
                                SizedBox(
                                  width: width,
                                  child: _toolCard(
                                    title: 'My PDFs',
                                    icon: Icons.picture_as_pdf_rounded,
                                    color: const Color(0xFFE76D78),
                                    onTap: () {
                                      _openScreen(const MyPdfsScreen());
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _toolCard(
                                    title: 'Summaries',
                                    icon: Icons.auto_awesome_rounded,
                                    color: _primaryColor,
                                    onTap: () {
                                      _openScreen(
                                        const SummaryListScreen(),
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: width,
                                  child: _toolCard(
                                    title: 'Dashboard',
                                    icon: Icons.dashboard_rounded,
                                    color: const Color(0xFF209C86),
                                    onTap: () {
                                      _openScreen(
                                        const DashboardScreen(),
                                      );
                                    },
                                  ),
                                ),

                                SizedBox(
                                width: width,
                                child: _toolCard(
                                  title: 'Security Inspector',
                                  icon: Icons.policy_outlined,
                                  color: const Color(0xFF3978B8),
                                  onTap: () {
                                    _openScreen(const DocumentSecurityScreen());
                                  },
                                ),
                              ),

                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildGamesCard(context),

                        const SizedBox(height: 28),
                        Text(
                          'Your notes',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Find an idea or start a new one.',
                          style: TextStyle(
                            color: secondaryColor,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            setState(() {
                              _searchQuery = value.trim().toLowerCase();
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search titles and content...',
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
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                StreamBuilder<List<NoteModel>>(
                  stream: _notesStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: _messagePanel(
                          icon: Icons.cloud_off_rounded,
                          title: 'Could not load notes',
                          message: _notesError(snapshot.error),
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

                    final allNotes = snapshot.data ?? <NoteModel>[];

                    if (allNotes.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _messagePanel(
                          icon: Icons.note_add_outlined,
                          title: 'Your first note starts here',
                          message:
                              'Save a definition, a useful example, '
                              'or an idea you want to remember.',
                          action: TextButton.icon(
                            onPressed: () {
                              _openScreen(const CreateNoteScreen());
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create your first note'),
                          ),
                        ),
                      );
                    }

                    final notes = allNotes.where((note) {
                      return note.title
                              .toLowerCase()
                              .contains(_searchQuery) ||
                          note.content
                              .toLowerCase()
                              .contains(_searchQuery);
                    }).toList();

                    if (notes.isEmpty) {
                      return SliverToBoxAdapter(
                        child: _messagePanel(
                          icon: Icons.search_off_rounded,
                          title: 'No matching notes',
                          message:
                              'Try another word from the title '
                              'or content of your note.',
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
                            final note = notes[index];

                            return Padding(
                              key: ValueKey(note.id),
                              padding: const EdgeInsets.only(
                                bottom: 10,
                              ),
                              child: NoteCard(note: note),
                            );
                          },
                          childCount: notes.length,
                        ),
                      ),
                    );
                  },
                ),
                // Space so the create button does not cover the last note.
                const SliverToBoxAdapter(
                  child: SizedBox(height: 100),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _openScreen(const CreateNoteScreen());
        },
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Create Note',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildGamesCard(BuildContext context) {
  return Padding(
    padding: EdgeInsets.zero,
    child: Material(
      color: const Color(0xFF27204A),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PacketRescueScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF443675),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.sports_esports_rounded,
                      color: Color(0xFFC4B5FD),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Games',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Learn through play',
                          style: TextStyle(
                            color: Color(0xFFCEC6E8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Can you rescue the packet?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Build connections, repair broken routes, '
                'and deliver your packet to the server.',
                style: TextStyle(
                  color: Color(0xFFCEC6E8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              const Wrap(
                spacing: 16,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        color: Color(0xFFC4B5FD),
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '4 missions',
                        style: TextStyle(color: Color(0xFFCEC6E8)),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Play Packet Rescue',
                        style: TextStyle(
                          color: Color(0xFFB9F6D2),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Color(0xFFB9F6D2),
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _toolCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1C1C2C) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 25,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  color: isDark
                      ? Colors.white
                      : const Color(0xFF202238),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          Icon(
            icon,
            size: 48,
            color: _primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? Colors.white
                  : const Color(0xFF202238),
              fontSize: 20,
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
            const SizedBox(height: 14),
            action,
          ],
        ],
      ),
    );
  }
}