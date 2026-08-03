import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_api.dart';
import '../services/auth_session_manager.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/action_feedback.dart';
import 'admin_dashboard_screen.dart';
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
  bool obscurePassword = true;
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
    final password = passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Please enter your LMS username and password.';
      });
      return;
    }

    await _loginLmsUser(role: role, username: username, password: password);
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
      await showActionConfirmation(
        context,
        title: 'Logged in successfully',
        message: 'Welcome back to EACC Connect.',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) {
            if (role == 'admin') {
              return AdminDashboardScreen(session: session);
            }
            return role == 'student'
                ? StudentCoursesScreen(session: session)
                : TeacherCoursesScreen(session: session);
          },
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
    } on http.ClientException catch (_) {
      if (!mounted) return;
      setState(
        () => errorMessage =
            'Could not reach the EACC backend. Check your internet connection and try again.',
      );
    } catch (error, stackTrace) {
      debugPrint('Unexpected login error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => errorMessage = _unexpectedLoginErrorMessage(error));
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

    if (error.code == 'unauthorized-domain' ||
        error.message?.contains('unauthorized domain') == true) {
      return 'This website is not allowed in Firebase Authentication yet. Add it2-gif.github.io to Firebase Auth authorized domains.';
    }

    if (error.code == 'invalid-custom-token' ||
        error.code == 'custom-token-mismatch') {
      return 'The backend Firebase token does not match this Firebase project.';
    }

    if (error.code == 'network-request-failed') {
      return 'Firebase could not finish secure sign-in. Check your connection and try again.';
    }

    return error.message ?? 'Firebase could not complete the secure sign-in.';
  }

  String _unexpectedLoginErrorMessage(Object error) {
    final details = error.toString();
    final lowerDetails = details.toLowerCase();

    if (lowerDetails.contains('unauthorized-domain') ||
        lowerDetails.contains('unauthorized domain')) {
      return 'This website is not allowed in Firebase Authentication yet. Add it2-gif.github.io to Firebase Auth authorized domains.';
    }

    if (lowerDetails.contains('failed to fetch') ||
        lowerDetails.contains('xmlhttprequest') ||
        lowerDetails.contains('clientexception') ||
        lowerDetails.contains('socketexception')) {
      return 'Could not reach the EACC backend. Check your internet connection and try again.';
    }

    return 'Login reached the backend, but secure sign-in could not finish. Please refresh and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 390;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.sky.withValues(alpha: 0.8),
              AppColors.background,
              Colors.white,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 24,
                vertical: compact ? 18 : 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Container(
                  padding: EdgeInsets.all(compact ? 20 : 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryDark.withValues(alpha: 0.12),
                        blurRadius: 34,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.asset(
                              'eacc-blue-logo.png',
                              height: compact ? 88 : 110,
                              width: compact ? 190 : 220,
                              fit: BoxFit.contain,
                              semanticLabel: 'Egyptian American Center',
                            ),
                          ),
                          SizedBox(height: compact ? 14 : 18),
                          const Text(
                            'EACC Connect',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Secure course messaging for students and teachers.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: compact ? 18 : 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withValues(alpha: 0.08),
                              AppColors.sky.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selectedRole == 'student'
                                  ? Icons.school_outlined
                                  : selectedRole == 'teacher'
                                  ? Icons.menu_book_outlined
                                  : Icons.admin_panel_settings_outlined,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                selectedRole == 'student'
                                    ? 'Student login'
                                    : selectedRole == 'teacher'
                                    ? 'Teacher login'
                                    : 'Admin login',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            const _RoleDot(label: 'LMS'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
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
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => selectedRole = value!);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: usernameController,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Username or email',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: passwordController,
                        autofillHints: const [AutofillHints.password],
                        obscureText: obscurePassword,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(
                                () => obscurePassword = !obscurePassword,
                              );
                            },
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                          ),
                        ),
                        onSubmitted: (_) => login(),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedRole == 'admin'
                                    ? 'Admin sign-in is verified through the EACC LMS.'
                                    : 'This sign-in is verified through the EACC LMS.',
                                textAlign: TextAlign.left,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: errorMessage == null
                            ? const SizedBox(height: 12)
                            : Padding(
                                key: ValueKey(errorMessage),
                                padding: const EdgeInsets.only(top: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.danger.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.danger,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          errorMessage!,
                                          textAlign: TextAlign.left,
                                          style: const TextStyle(
                                            color: AppColors.danger,
                                            fontWeight: FontWeight.w700,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 22),
                      AnimatedScale(
                        scale: isLoading ? 0.99 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : login,
                          icon: isLoading
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login),
                          label: Text(
                            isLoading ? 'Signing in...' : 'Login',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'EACC Connect keeps course communication organized and role-based.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleDot extends StatelessWidget {
  final String label;

  const _RoleDot({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.primaryDark,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
