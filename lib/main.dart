import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/session_manager.dart';
import 'features/notes/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SessionManager.instance.initialize();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = SessionManager.instance;

    return AnimatedBuilder(
      animation: session,
      builder: (context, child) {
        return MaterialApp(
          key: ValueKey(session.isLoggedIn),
          debugShowCheckedModeBanner: false,
          title: 'AI Study Notes',
          home: session.isLoggedIn
              ? const HomeScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}