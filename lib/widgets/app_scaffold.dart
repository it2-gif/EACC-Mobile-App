import 'package:flutter/foundation.dart';
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
        title: Text(title),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
        actions: [
          ...?actions,
          // ── Debug-only: test the notification banner ──────────────────────
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Test notification banner',
              onPressed: () =>
                  PushNotificationService.instance.showTestBanner(),
            ),
          // ─────────────────────────────────────────────────────────────────
          if (showLogout)
            IconButton(
              onPressed: () async => _logout(context),
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
            ),
        ],
      ),
      body: body,
    );
  }
}
