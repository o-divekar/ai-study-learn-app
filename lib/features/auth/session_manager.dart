import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'auth_controller.dart';

class SessionManager extends ChangeNotifier
    with WidgetsBindingObserver {
  SessionManager._();

  static final SessionManager instance = SessionManager._();

  static const sessionDuration = Duration(hours: 24);

  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<User?>? _authSubscription;
  Timer? _expiryTimer;

  DateTime? _expiresAt;
  bool _isLoggedIn = false;
  bool _isSigningOut = false;

  bool get isLoggedIn => _isLoggedIn;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

    // Wait for Firebase to restore the saved authentication state.
    final user = await _auth.authStateChanges().first;

    if (user != null) {
      try {
        await activateSession();
      } catch (e) {
        debugPrint('Saved session could not be restored: $e');
        await _auth.signOut();
      }
    }

    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _clearSession();
      }

      // Do not automatically admit newly signed-in users here.
      // LoginScreen first checks email verification.
    });
  }

  Future<void> activateSession() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'session-missing',
        message: 'Please log in again.',
      );
    }

    // Refresh the token, including the verified-email claim.
    final token = await user.getIdTokenResult(true);

    if (token.claims?['email_verified'] != true) {
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message: 'Please verify your email before logging in.',
      );
    }

    final authenticationTime = token.authTime;

    if (authenticationTime == null) {
      throw FirebaseAuthException(
        code: 'session-missing',
        message: 'Your session could not be checked. Please log in again.',
      );
    }

    // Token refresh does not start a new 24-hour session.
    final expiry = authenticationTime.toUtc().add(sessionDuration);

    if (!DateTime.now().toUtc().isBefore(expiry)) {
      throw FirebaseAuthException(
        code: 'session-expired',
        message: 'Your session has expired. Please log in again.',
      );
    }

    _expiresAt = expiry;
    _isLoggedIn = true;

    _scheduleExpiry();
    notifyListeners();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();

    final expiry = _expiresAt;
    if (expiry == null) return;

    final remaining = expiry.difference(DateTime.now().toUtc());

    if (remaining <= Duration.zero) {
      unawaited(signOut());
      return;
    }

    _expiryTimer = Timer(remaining, () {
      unawaited(signOut());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isLoggedIn) {
      // Timers may pause while the app is in the background.
      _scheduleExpiry();
    }
  }

  Future<void> signOut() async {
    if (_isSigningOut) return;

    _isSigningOut = true;

    // Remove protected screens immediately.
    _clearSession();

    try {
      await AuthController().logout();
    } catch (e) {
      debugPrint('Sign-out error: $e');

      // AuthController.logout also signs Firebase out in its finally block.
      // Retry Firebase directly if necessary.
      try {
        await _auth.signOut();
      } catch (error) {
        debugPrint('Firebase sign-out failed: $error');
      }
    } finally {
      _isSigningOut = false;
    }
  }

  void _clearSession() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _expiresAt = null;

    if (_isLoggedIn) {
      _isLoggedIn = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }
}