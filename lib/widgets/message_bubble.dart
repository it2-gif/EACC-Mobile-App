import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'video_message_player.dart';
import 'voice_message_player.dart';

class MessageBubble extends StatelessWidget {
  final String type;
  final String text;
  final String? mediaUrl;
  final int? durationMs;
  final String senderName;
  final String senderRole;
  final String currentUserRole;
  final String currentSenderName;
  final dynamic createdAt;

  const MessageBubble({
    super.key,
    required this.type,
    required this.text,
    required this.mediaUrl,
    this.durationMs,
    required this.senderName,
    required this.senderRole,
    required this.currentUserRole,
    required this.currentSenderName,
    required this.createdAt,
  });

  bool get isMe {
    if (currentUserRole == 'admin') return false;
    return senderRole == currentUserRole && senderName == currentSenderName;
  }

  String get roleLabel {
    switch (senderRole) {
      case 'student':
        return 'Student';
      case 'teacher':
        return 'Teacher';
      case 'admin':
        return 'Admin';
      default:
        return senderRole;
    }
  }

  String get displaySender {
    if (senderRole == 'admin') return 'EACC Admin - Admin';
    return '$senderName - $roleLabel';
  }

  Color get nameColor {
    switch (senderRole) {
      case 'student':
        return AppColors.student;
      case 'teacher':
        return AppColors.teacher;
      case 'admin':
        return AppColors.admin;
      default:
        return AppColors.primary;
    }
  }

  IconData get roleIcon {
    switch (senderRole) {
      case 'student':
        return Icons.school;
      case 'teacher':
        return Icons.menu_book;
      case 'admin':
        return Icons.admin_panel_settings;
      default:
        return Icons.person;
    }
  }

  void _openImage(BuildContext context) {
    if (mediaUrl == null || mediaUrl!.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  mediaUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Could not load image',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final time = formatMessageTime(createdAt);
    final isImage = type == 'image' && mediaUrl != null && mediaUrl!.isNotEmpty;
    final isVideo = type == 'video' && mediaUrl != null && mediaUrl!.isNotEmpty;
    final isVoice = type == 'voice' && mediaUrl != null && mediaUrl!.isNotEmpty;
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.78;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxBubbleWidth.clamp(240, 420).toDouble(),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isMe ? AppColors.bubbleMe : AppColors.bubbleOther,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(12),
              topRight: const Radius.circular(12),
              bottomLeft: Radius.circular(isMe ? 12 : 4),
              bottomRight: Radius.circular(isMe ? 4 : 12),
            ),
            border: Border.all(
              color: isMe
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(roleIcon, size: 14, color: nameColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      displaySender,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: nameColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              if (isImage)
                GestureDetector(
                  onTap: () => _openImage(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      mediaUrl!,
                      width: double.infinity,
                      height: 190,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;

                        return Container(
                          height: 190,
                          alignment: Alignment.center,
                          color: AppColors.background,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          height: 120,
                          alignment: Alignment.center,
                          color: AppColors.background,
                          child: const Text('Could not load image'),
                        );
                      },
                    ),
                  ),
                )
              else if (isVideo)
                VideoMessagePlayer(url: mediaUrl!)
              else if (isVoice)
                VoiceMessagePlayer(url: mediaUrl!, durationMs: durationMs)
              else
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 15, height: 1.35),
                ),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    time,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
