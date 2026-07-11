import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../screens/support_chat_screen.dart';
import '../theme/app_theme.dart';

class SupportHelpButton extends StatelessWidget {
  final AuthSession session;

  const SupportHelpButton({super.key, required this.session});

  bool get _isSupportAgent => session.appUser.isTechnicalSupport;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'technical-support-help',
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        onPressed: () => _openSupport(context),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.support_agent_rounded),
            Positioned(
              right: -1,
              top: -1,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.85, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOut,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF21C55D),
                    border: Border.all(color: Colors.white, width: 1.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
        label: Text(
          _isSupportAgent ? 'Support Inbox' : 'Live Help',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  void _openSupport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _isSupportAgent
            ? SupportInboxScreen(session: session)
            : SupportChatScreen(session: session),
      ),
    );
  }
}
