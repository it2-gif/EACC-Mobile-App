import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'models/auth_session.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_courses_screen.dart';
import 'screens/teacher_courses_screen.dart';
import 'services/auth_session_manager.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(EaccChatApp(initialSessionLoader: _bootstrapInitialSession()));
}

Future<AuthSession?> _bootstrapInitialSession() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  return _restoreInitialSession();
}

Future<AuthSession?> _restoreInitialSession() async {
  try {
    final session = await AuthSessionManager().restore().timeout(
      const Duration(seconds: 10),
    );
    unawaited(_initializeNotifications(session));
    return session;
  } catch (error, stackTrace) {
    debugPrint('Session restore failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    unawaited(_initializeNotifications(null));
    return null;
  }
}

Future<void> _initializeNotifications(AuthSession? session) async {
  try {
    await PushNotificationService.instance
        .initialize(initialSession: session)
        .timeout(const Duration(seconds: 12));
    await PushNotificationService.instance.openBrowserNotificationLaunch();
  } catch (error, stackTrace) {
    debugPrint('Notification initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class EaccChatApp extends StatelessWidget {
  final Future<AuthSession?> initialSessionLoader;

  const EaccChatApp({super.key, required this.initialSessionLoader});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EACC Connection',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: PushNotificationService.instance.navigatorKey,
      scaffoldMessengerKey:
          PushNotificationService.instance.scaffoldMessengerKey,
      home: _InitialSessionGate(sessionLoader: initialSessionLoader),
    );
  }
}

class _InitialSessionGate extends StatelessWidget {
  final Future<AuthSession?> sessionLoader;

  const _InitialSessionGate({required this.sessionLoader});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthSession?>(
      future: sessionLoader,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _StartupScreen();
        }

        if (snapshot.hasError) {
          return _StartupErrorScreen(
            message:
                'Firebase could not finish starting the app. Refresh the page and try again.',
          );
        }

        final session = snapshot.data;
        if (session == null) return const LoginScreen();

        if (session.appUser.role == 'student') {
          return StudentCoursesScreen(session: session);
        }

        if (session.appUser.role == 'teacher') {
          return TeacherCoursesScreen(session: session);
        }

        if (session.appUser.role == 'admin') {
          return AdminDashboardScreen(session: session);
        }

        return const LoginScreen();
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 34,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text(
                'Opening EACC Connection...',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final String message;

  const _StartupErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 42,
                color: AppColors.danger,
              ),
              const SizedBox(height: 14),
              const Text(
                'EACC Connection could not start',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
