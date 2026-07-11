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
    return FloatingActionButton.extended(
      heroTag: 'technical-support-help',
      backgroundColor: AppColors.primaryDark,
      foregroundColor: Colors.white,
      elevation: 5,
      onPressed: () => _openSupport(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.support_agent_rounded),
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: const Color(0xFF21C55D),
                border: Border.all(color: Colors.white, width: 1.5),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isSupportAgent ? 'Support Inbox' : 'Live Help',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
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
