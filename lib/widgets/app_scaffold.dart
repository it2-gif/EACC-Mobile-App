import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../screens/login_screen.dart';
import '../services/auth_session_manager.dart';
import '../services/push_notification_service.dart';

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
    await AuthSessionManager().logout();
    await PushNotificationService.instance.deactivate();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Logged out successfully.')));

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
            IconButton(
              onPressed: () async => _logout(context),
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
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
