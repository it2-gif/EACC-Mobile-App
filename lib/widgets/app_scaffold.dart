import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../services/auth_session_manager.dart';
import '../services/push_notification_service.dart';
import 'action_feedback.dart';

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final bool showLogout;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.showLogout = true,
  });

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text(
              'Logout',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthSessionManager().logout();
    await PushNotificationService.instance.deactivate();
    if (!context.mounted) return;
    await showActionConfirmation(
      context,
      title: 'Logged out successfully',
      message: 'Your EACC Connect session was closed.',
      icon: Icons.logout_rounded,
      color: AppColors.danger,
    );

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final maxContentWidth = width >= 1100 ? 1080.0 : 760.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: width >= 900 ? 68 : 60,
        title: Text(title),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          ...?actions,
          if (showLogout)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () async => _logout(context),
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Logout'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.sky.withValues(alpha: 0.55),
              AppColors.background,
              Colors.white.withValues(alpha: 0.72),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: body,
            ),
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
