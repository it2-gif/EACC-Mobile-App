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
  final dynamic editedAt;
  final dynamic deletedAt;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
    required this.editedAt,
    required this.deletedAt,
    this.onEdit,
    this.onDelete,
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
    if (senderRole == 'admin') return 'EACC Admin';
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

  bool get isDeleted => deletedAt != null;

  bool get isEdited => editedAt != null && !isDeleted;

  bool get canShowActions => onEdit != null || onDelete != null;

  bool get canEdit => onEdit != null && type == 'text' && !isDeleted;

  bool get canDelete => onDelete != null && !isDeleted;

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
    final bubbleColor = isMe ? AppColors.bubbleMe : AppColors.bubbleOther;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxBubbleWidth.clamp(240, 420).toDouble(),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 6),
              bottomRight: Radius.circular(isMe ? 6 : 16),
            ),
            border: Border.all(
              color: isMe
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : AppColors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 6),
              bottomRight: Radius.circular(isMe ? 6 : 16),
            ),
            child: Container(
              color: bubbleColor,
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: nameColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(roleIcon, size: 13, color: nameColor),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          displaySender,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: nameColor,
                          ),
                        ),
                      ),
                      if (canShowActions)
                        _MessageActionsMenu(
                          canEdit: canEdit,
                          canDelete: canDelete,
                          onEdit: onEdit,
                          onDelete: onDelete,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (isDeleted)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.block_rounded,
                          size: 16,
                          color: AppColors.muted,
                        ),
                        SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'This message was deleted',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: AppColors.muted,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (isImage)
                    GestureDetector(
                      onTap: () => _openImage(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Image.network(
                              mediaUrl!,
                              width: double.infinity,
                              height: 200,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;

                                    return Container(
                                      height: 200,
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
                            Positioned(
                              left: 10,
                              bottom: 10,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.48),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    'Tap to open',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (isVideo)
                    _MediaFrame(child: VideoMessagePlayer(url: mediaUrl!))
                  else if (isVoice)
                    _MediaFrame(
                      child: VoiceMessagePlayer(
                        url: mediaUrl!,
                        durationMs: durationMs,
                      ),
                    )
                  else
                    SelectableText(
                      text,
                      style: const TextStyle(
                        fontSize: 15.25,
                        height: 1.45,
                        color: AppColors.ink,
                      ),
                    ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          if (isEdited)
                            const Text(
                              'Edited',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Text(
                            time,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageActionsMenu extends StatelessWidget {
  final bool canEdit;
  final bool canDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MessageActionsMenu({
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (!canEdit && !canDelete) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<_MessageAction>(
      tooltip: 'Message options',
      padding: EdgeInsets.zero,
      iconSize: 18,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      icon: const Icon(Icons.more_horiz_rounded, color: AppColors.muted),
      onSelected: (action) {
        switch (action) {
          case _MessageAction.edit:
            onEdit?.call();
            break;
          case _MessageAction.delete:
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(
            value: _MessageAction.edit,
            child: _MessageActionRow(
              icon: Icons.edit_outlined,
              label: 'Edit message',
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: _MessageAction.delete,
            child: _MessageActionRow(
              icon: Icons.delete_outline,
              label: 'Delete message',
              isDanger: true,
            ),
          ),
      ],
    );
  }
}

class _MessageActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDanger;

  const _MessageActionRow({
    required this.icon,
    required this.label,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.danger : AppColors.ink;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

enum _MessageAction { edit, delete }

class _MediaFrame extends StatelessWidget {
  final Widget child;

  const _MediaFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
      ),
      child: child,
    );
  }
}
