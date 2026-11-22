import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final nameController = TextEditingController();

  final authController = AuthController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _accountCreated = false;
  bool _emailSent = false;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  static const _primary = Color(0xFF6750E8);

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use':
          return 'This email already has an account. Please log in.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Choose a stronger password.';
        case 'network-request-failed':
          return 'Check your internet connection and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait before trying again.';
        default:
          return error.message ?? 'Something went wrong. Try again.';
      }
    }

    return 'The request could not be completed. Please try again.';
  }

  void _startResendTimer() {
    _resendTimer?.cancel();

    setState(() {
      _resendSeconds = 60;
    });

    _resendTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _resendSeconds--;
        });

        if (_resendSeconds == 0) {
          timer.cancel();
        }
      },
    );
  }

  Future<void> signup() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      await authController.signUp(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        // Do not remove intentional spaces from passwords.
        password: passwordController.text,
      );

      if (!mounted) return;

      setState(() {
        _accountCreated = true;
      });

      // Account creation and email delivery are separate operations.
      await _sendVerification();
    } catch (e) {
      _showMessage(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendVerification() async {
    final user = authController.currentUser;

    if (user == null) {
      _showMessage('Please log in again to verify your email.');
      return;
    }

    try {
      await user.sendEmailVerification();

      if (!mounted) return;

      setState(() {
        _emailSent = true;
      });

      _startResendTimer();
      _showMessage('Verification email sent. Check your inbox and spam.');
    } catch (e) {
      _showMessage(
        'Your account exists, but the verification email '
        'could not be sent. ${_errorMessage(e)}',
      );
    }
  }

  Future<void> _resendVerification() async {
    if (_isLoading || _resendSeconds > 0) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _sendVerification();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _backToLogin() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_accountCreated) {
        await authController.logout();
      }

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      _showMessage(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(
    String label,
    IconData icon, {
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF29293B)
          : const Color(0xFFF7F8FC),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).dividerColor,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark ? Colors.white70 : Colors.black54;

    return PopScope(
      // Route exits go through _backToLogin to clear the session.
      canPop: !_accountCreated && !_isLoading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isLoading) {
          _backToLogin();
        }
      },
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF11111D) : const Color(0xFFF5F5FF),
        appBar: AppBar(
          title: const Text('Signup'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _isLoading ? null : _backToLogin,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.auto_stories_rounded,
                      size: 60,
                      color: _primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _accountCreated
                          ? 'Check your email'
                          : 'Start learning smarter',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _accountCreated
                          ? 'Verify your email address to continue.'
                          : 'Create your AI Study Notes account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondary, height: 1.5),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C2C)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: _accountCreated
                          ? Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                const Icon(
                                  Icons.mark_email_unread_outlined,
                                  size: 48,
                                  color: _primary,
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  emailController.text.trim(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _emailSent
                                      ? 'Open the verification link in your '
                                          'email, then return to login. '
                                          'Check your spam folder too.'
                                      : 'Your account has been created. '
                                          'Tap below to send your '
                                          'verification email.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: secondary,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                OutlinedButton(
                                  onPressed: _isLoading ||
                                          _resendSeconds > 0
                                      ? null
                                      : _resendVerification,
                                  child: Text(
                                    _resendSeconds > 0
                                        ? 'Resend in ${_resendSeconds}s'
                                        : _emailSent
                                            ? 'Resend verification email'
                                            : 'Send verification email',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed:
                                      _isLoading ? null : _backToLogin,
                                  child: const Text('Back to Login'),
                                ),
                                if (_isLoading) ...[
                                  const SizedBox(height: 16),
                                  const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ],
                              ],
                            )
                          : Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    controller: nameController,
                                    enabled: !_isLoading,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.next,
                                    decoration: _decoration(
                                      'Full Name',
                                      Icons.person_outline_rounded,
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Please enter your name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: emailController,
                                    enabled: !_isLoading,
                                    keyboardType:
                                        TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    autocorrect: false,
                                    decoration: _decoration(
                                      'Email',
                                      Icons.mail_outline_rounded,
                                    ),
                                    validator: (value) {
                                      final email = value?.trim() ?? '';
                                      if (!RegExp(
                                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                      ).hasMatch(email)) {
                                        return 'Enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: passwordController,
                                    enabled: !_isLoading,
                                    obscureText: _obscurePassword,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => signup(),
                                    decoration: _decoration(
                                      'Password',
                                      Icons.lock_outline_rounded,
                                      suffixIcon: IconButton(
                                        tooltip: _obscurePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.length < 8) {
                                        return 'Use at least 8 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 26),
                                  ElevatedButton(
                                    onPressed: _isLoading ? null : signup,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primary,
                                      foregroundColor: Colors.white,
                                      minimumSize:
                                          const Size.fromHeight(54),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Create Account',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}