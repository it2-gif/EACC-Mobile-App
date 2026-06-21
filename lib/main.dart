import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'models/auth_session.dart';
import 'screens/login_screen.dart';
import 'screens/student_courses_screen.dart';
import 'screens/teacher_courses_screen.dart';
import 'services/auth_session_manager.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final session = await AuthSessionManager().restore();
  runApp(EaccChatApp(initialSession: session));

  unawaited(_initializeNotifications(session));
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
  final AuthSession? initialSession;

  const EaccChatApp({super.key, this.initialSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EACC Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: PushNotificationService.instance.navigatorKey,
      scaffoldMessengerKey:
          PushNotificationService.instance.scaffoldMessengerKey,
      home: _initialScreen(),
    );
  }

  Widget _initialScreen() {
    final session = initialSession;
    if (session == null) return const LoginScreen();

    if (session.appUser.role == 'student') {
      return StudentCoursesScreen(session: session);
    }

    if (session.appUser.role == 'teacher') {
      return TeacherCoursesScreen(session: session);
    }

    return const LoginScreen();
  }
}
