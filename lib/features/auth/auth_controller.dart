import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Shared initialization across AuthController instances.
  static Future<void>? _googleInitialization;

  Future<void> _initializeGoogle() {
    return _googleInitialization ??=
        GoogleSignIn.instance.initialize();
  }

  // EMAIL/PASSWORD SIGNUP
  Future<UserCredential> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final userCredential =
        await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = userCredential.user!;

    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name.trim(),
      'email': user.email,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return userCredential;
  }

  // EMAIL/PASSWORD LOGIN
  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // GOOGLE LOGIN
  // Returns null when the user closes/cancels Google sign-in.
  Future<UserCredential?> signInWithGoogle() async {
    UserCredential userCredential;

    try {
      if (kIsWeb) {
        // Firebase handles Google authentication on Flutter web.
        final provider = GoogleAuthProvider();
        provider.setCustomParameters({
          'prompt': 'select_account',
        });

        userCredential = await _auth.signInWithPopup(provider);
      } else {
        await _initializeGoogle();

        final googleUser =
            await GoogleSignIn.instance.authenticate();

        final googleAuthentication = googleUser.authentication;
        final idToken = googleAuthentication.idToken;

        if (idToken == null) {
          throw FirebaseAuthException(
            code: 'missing-google-id-token',
            message:
                'Google sign-in could not obtain an ID token. '
                'Check the Firebase Android configuration.',
          );
        }

        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
        );

        userCredential =
            await _auth.signInWithCredential(credential);
      }
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      rethrow;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null;
      }
      rethrow;
    }

    final user = userCredential.user;

    if (user == null) {
      throw FirebaseAuthException(
        code: 'missing-user',
        message: 'Google sign-in did not return a user.',
      );
    }

    try {
      await _createGoogleProfileIfMissing(user);
    } catch (_) {
      // Avoid leaving a partial login when profile creation fails.
      await _auth.signOut();
      rethrow;
    }

    return userCredential;
  }

  Future<void> _createGoogleProfileIfMissing(User user) async {
    final userRef = _firestore.collection('users').doc(user.uid);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);

      // Preserve existing profile details and creation date.
      if (!snapshot.exists) {
        transaction.set(userRef, {
          'uid': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'photoUrl': user.photoURL ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // LOGOUT
  Future<void> logout() async {
    try {
      if (!kIsWeb && _googleInitialization != null) {
        await _googleInitialization;
        await GoogleSignIn.instance.signOut();
      }
    } finally {
      await _auth.signOut();
    }
  }

  // PASSWORD RESET
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(
      email: email.trim(),
    );
  }

  User? get currentUser => _auth.currentUser;
}