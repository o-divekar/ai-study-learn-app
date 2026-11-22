import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_controller.dart';
import 'forget_password_screen.dart';
import 'session_manager.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final authController = AuthController();

  bool _isLoading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;

  static const _primaryColor = Color(0xFF6750E8);

  Future<void> login() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _googleLoading = false;
    });

    try {
      await authController.login(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      await _finishLogin();
    } on FirebaseAuthException catch (e) {
      _showMessage(_authErrorMessage(e));
    } catch (e) {
      debugPrint('Login failed: $e');
      _showMessage('Unable to finish login. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _googleLogin() async {
    if (_isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _googleLoading = true;
    });

    try {
      final result = await authController.signInWithGoogle();

      if (result == null) return;

      await _finishLogin();
    } on FirebaseAuthException catch (e) {
      _showMessage(_authErrorMessage(e));
    } catch (e) {
      debugPrint('Google login failed: $e');
      _showMessage(
        'Google sign-in could not finish. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _googleLoading = false;
        });
      }
    }
  }

  Future<void> _finishLogin() async {
    bool sessionActivated = false;

    try {
      final auth = FirebaseAuth.instance;
      await auth.currentUser?.reload();

      final user = auth.currentUser;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'session-missing',
          message: 'Please log in again.',
        );
      }

      if (!mounted) return;

      if (!user.emailVerified) {
        final resend = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Verify your email'),
              content: Text(
                'Open the verification link sent to '
                '${user.email ?? 'your email address'}.\n\n'
                'Check your inbox and spam folder, '
                'then log in again.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Resend email'),
                ),
              ],
            );
          },
        );

        if (resend == true) {
          await user.sendEmailVerification();

          _showMessage(
            'Verification email sent. Open the link, then log in.',
          );
        }

        return;
      }

      await SessionManager.instance.activateSession();
      sessionActivated = true;

      // main.dart automatically opens Home.
      // Do not push HomeScreen manually here.
    } finally {
      if (!sessionActivated) {
        await authController.logout();
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

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'The email or password is incorrect.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';

      case 'network-request-failed':
        return 'Check your internet connection and try again.';

      case 'account-exists-with-different-credential':
        return 'This email uses another sign-in method. '
            'Please use your existing login method.';

      case 'operation-not-allowed':
        return 'This sign-in method is not enabled in Firebase.';

      default:
        return error.message ?? 'Login failed. Please try again.';
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor:
          isDark ? const Color(0xFF252536) : const Color(0xFFF7F8FC),
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

  Widget _spinner(Color color) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color,
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
        title: Text(
          'Login',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
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
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF8B74FF),
                              _primaryColor,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: _primaryColor.withAlpha(55),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: Colors.white,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'AI STUDY NOTES',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your notes, ideas, and next breakthrough\n'
                      'are waiting for you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1C1C2C)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF303044)
                              : const Color(0xFFECECF6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(
                              isDark ? 30 : 10,
                            ),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Sign in to your account',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 24),
                              TextFormField(
                                controller: emailController,
                                enabled: !_isLoading,
                                keyboardType:
                                    TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [
                                  AutofillHints.email,
                                ],
                                autocorrect: false,
                                decoration: _inputDecoration(
                                  label: 'Email',
                                  hint: 'you@example.com',
                                  icon: Icons.mail_outline_rounded,
                                ),
                                validator: (value) {
                                  final email = value?.trim() ?? '';

                                  if (email.isEmpty) {
                                    return 'Please enter your email';
                                  }

                                  if (!RegExp(
                                    r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                  ).hasMatch(email)) {
                                    return 'Please enter a valid email';
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
                                autofillHints: const [
                                  AutofillHints.password,
                                ],
                                onFieldSubmitted: (_) => login(),
                                decoration: _inputDecoration(
                                  label: 'Password',
                                  hint: 'Enter your password',
                                  icon: Icons.lock_outline_rounded,
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: _isLoading
                                        ? null
                                        : () {
                                            setState(() {
                                              _obscurePassword =
                                                  !_obscurePassword;
                                            });
                                          },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 21,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ForgotPasswordScreen(),
                                            ),
                                          );
                                        },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _primaryColor,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _isLoading ? null : login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryColor,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      _primaryColor.withAlpha(150),
                                  disabledForegroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(54),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading && !_googleLoading
                                    ? _spinner(Colors.white)
                                    : const Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 24),
                              Row(
                                children: [
                                  const Expanded(child: Divider()),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Text(
                                      'or continue with',
                                      style: TextStyle(
                                        color: secondaryColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const Expanded(child: Divider()),
                                ],
                              ),
                              const SizedBox(height: 24),
                              OutlinedButton.icon(
                                onPressed:
                                    _isLoading ? null : _googleLogin,
                                icon: _googleLoading
                                    ? _spinner(_primaryColor)
                                    : const Icon(
                                        Icons.account_circle_outlined,
                                        size: 24,
                                      ),
                                label: Text(
                                  _googleLoading
                                      ? 'Signing in...'
                                      : 'Continue with Google',
                                  textAlign: TextAlign.center,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: textColor,
                                  minimumSize: const Size.fromHeight(54),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 14,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  side: BorderSide(
                                    color: isDark
                                        ? const Color(0xFF42425A)
                                        : const Color(0xFFDEE0EB),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          "Don't have an account?",
                          style: TextStyle(color: secondaryColor),
                        ),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SignupScreen(),
                                    ),
                                  );
                                },
                          style: TextButton.styleFrom(
                            foregroundColor: _primaryColor,
                          ),
                          child: const Text(
                            'Create Account',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
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