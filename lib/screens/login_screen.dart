import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_api.dart';
import '../services/auth_session_manager.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import 'student_courses_screen.dart';
import 'teacher_courses_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthApi? authApi;

  const LoginScreen({super.key, this.authApi});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String selectedRole = 'student';
  bool isLoading = false;
  String? errorMessage;

  final usernameController = TextEditingController();
  final passwordController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (isLoading) return;

    final role = selectedRole;
    final username = usernameController.text.trim();
    final password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your LMS username and password.';
      });
      return;
    }

    if (role == 'student' || role == 'teacher') {
      await _loginLmsUser(role: role, username: username, password: password);
      return;
    }

    setState(() {
      errorMessage =
          'Admin login is not connected yet. Student and teacher sign-in are live now.';
    });
  }

  Future<void> _loginLmsUser({
    required String role,
    required String username,
    required String password,
  }) async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final session = await (widget.authApi ?? AuthApi()).login(
        role: role,
        username: username,
        password: password,
      );
      await PushNotificationService.instance.activate(session);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => role == 'student'
              ? StudentCoursesScreen(session: session)
              : TeacherCoursesScreen(session: session),
        ),
      );
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = error.message);
    } on AuthSessionException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = error.message);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = _firebaseErrorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => errorMessage =
            'Could not reach the EACC backend. Make sure it is running.',
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    if (error.code == 'configuration-not-found' ||
        error.message?.contains('CONFIGURATION_NOT_FOUND') == true) {
      return 'Firebase Authentication is not enabled for this project.';
    }

    return error.message ?? 'Firebase could not complete the secure sign-in.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'eacc-blue-logo.png',
                        height: 132,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        semanticLabel: 'Egyptian American Center',
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'EACC Chat',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Secure course messaging for students, teachers, and admins',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 32),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Login as',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'student',
                          child: Text('Student'),
                        ),
                        DropdownMenuItem(
                          value: 'teacher',
                          child: Text('Teacher'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (value) {
                        setState(() => selectedRole = value!);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username or email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onSubmitted: (_) => login(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      selectedRole == 'admin'
                          ? 'Admin sign-in will be enabled after the real LMS admin integration is completed.'
                          : 'This sign-in is verified through the EACC LMS.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: isLoading ? null : login,
                      icon: isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(
                        isLoading ? 'Signing in...' : 'Login',
                        style: const TextStyle(fontSize: 16),
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
