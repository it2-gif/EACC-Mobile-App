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
  final bool showLogout;

  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
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
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
            ),
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
      message: 'Your EACC Connection session was closed.',
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        toolbarHeight: 60,
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
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: body,
          ),
        ),
      ),
    );
  }
}
