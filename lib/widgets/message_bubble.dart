import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'video_message_player.dart';
import 'voice_message_player.dart';

enum MessageDeliveryStatus { sending, sent, delivered, seen, failed }

class MessageBubble extends StatelessWidget {
  final String type;
  final String text;
  final String? mediaUrl;
  final String? fileName;
  final int? fileSizeBytes;
  final String? fileType;
  final int? durationMs;
  final List<Map<String, dynamic>>? attachments;
  final String senderName;
  final String senderRole;
  final String currentUserRole;
  final String currentSenderName;
  final dynamic createdAt;
  final dynamic editedAt;
  final dynamic deletedAt;
  final String? replySenderName;
  final String? replySenderRole;
  final String? replyPreview;
  final String? replyType;
  final bool forwarded;
  final bool pinned;
  final Map<String, dynamic>? reactions;
  final MessageDeliveryStatus? deliveryStatus;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onForward;
  final VoidCallback? onTogglePin;

  const MessageBubble({
    super.key,
    required this.type,
    required this.text,
    required this.mediaUrl,
    this.fileName,
    this.fileSizeBytes,
    this.fileType,
    this.durationMs,
    this.attachments,
    required this.senderName,
    required this.senderRole,
    required this.currentUserRole,
    required this.currentSenderName,
    required this.createdAt,
    required this.editedAt,
    required this.deletedAt,
    this.replySenderName,
    this.replySenderRole,
    this.replyPreview,
    this.replyType,
    this.forwarded = false,
    this.pinned = false,
    this.reactions,
    this.deliveryStatus,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReact,
    this.onForward,
    this.onTogglePin,
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

  bool get canShowActions =>
      onEdit != null ||
      onDelete != null ||
      onReact != null ||
      onForward != null ||
      onTogglePin != null;

  bool get canReply => onReply != null && !isDeleted;

  bool get canEdit => onEdit != null && type == 'text' && !isDeleted;

  bool get canDelete => onDelete != null && !isDeleted;

  bool get hasReplyPreview =>
      replyPreview != null &&
      replyPreview!.trim().isNotEmpty &&
      replySenderName != null &&
      replySenderName!.trim().isNotEmpty;

  String get replyRoleLabel {
    switch (replySenderRole) {
      case 'student':
        return 'Student';
      case 'teacher':
        return 'Teacher';
      case 'admin':
        return 'Admin';
      default:
        return '';
    }
  }

  String get replySenderLabel {
    if (replySenderRole == 'admin') return 'EACC Admin';
    final role = replyRoleLabel;
    if (role.isEmpty) return replySenderName ?? '';
    return '${replySenderName ?? ''} - $role';
  }

  String get deliveryStatusLabel {
    switch (deliveryStatus) {
      case MessageDeliveryStatus.sending:
        return 'Sending';
      case MessageDeliveryStatus.sent:
        return 'Sent';
      case MessageDeliveryStatus.delivered:
        return 'Delivered';
      case MessageDeliveryStatus.seen:
        return 'Seen';
      case MessageDeliveryStatus.failed:
        return 'Failed';
      case null:
        return '';
    }
  }

  IconData get deliveryStatusIcon {
    switch (deliveryStatus) {
      case MessageDeliveryStatus.sending:
        return Icons.schedule_rounded;
      case MessageDeliveryStatus.sent:
        return Icons.check_rounded;
      case MessageDeliveryStatus.delivered:
        return Icons.done_all_rounded;
      case MessageDeliveryStatus.seen:
        return Icons.done_all_rounded;
      case MessageDeliveryStatus.failed:
        return Icons.error_outline_rounded;
      case null:
        return Icons.check_rounded;
    }
  }

  Color get deliveryStatusColor {
    switch (deliveryStatus) {
      case MessageDeliveryStatus.seen:
        return AppColors.primary;
      case MessageDeliveryStatus.failed:
        return AppColors.danger;
      default:
        return AppColors.muted;
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
            Positioned(
              left: 12,
              right: 72,
              bottom: 16,
              child: FilledButton.icon(
                onPressed: _openMediaExternally,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Open or download'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMediaExternally() {
    final url = mediaUrl;
    if (url == null || url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  void _openAttachment(BuildContext context, Map<String, dynamic> attachment) {
    final url = attachment['media_url']?.toString() ?? '';
    if (url.isEmpty) return;

    final attachmentType = attachment['type']?.toString() ?? '';
    if (attachmentType == 'image') {
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  child: Image.network(
                    url,
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
              Positioned(
                left: 12,
                right: 72,
                bottom: 16,
                child: FilledButton.icon(
                  onPressed: () => _openUrl(url),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Open or download'),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    _openUrl(url);
  }

  void _openUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
  }

  void _openVideo(BuildContext context) {
    if (mediaUrl == null || mediaUrl!.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: VideoMessagePlayer(url: mediaUrl!),
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
            Positioned(
              left: 12,
              right: 72,
              bottom: 16,
              child: FilledButton.icon(
                onPressed: _openMediaExternally,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Open or download'),
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
    final isDocument =
        type == 'document' && mediaUrl != null && mediaUrl!.isNotEmpty;
    final groupAttachments = attachments ?? const <Map<String, dynamic>>[];
    final isMediaGroup = type == 'media_group' && groupAttachments.isNotEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = screenWidth * (screenWidth >= 900 ? 0.58 : 0.78);
    final bubbleColor = isMe ? AppColors.bubbleMe : AppColors.bubbleOther;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: canReply ? onReply : null,
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxBubbleWidth.clamp(250, 520).toDouble(),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 7),
                bottomRight: Radius.circular(isMe ? 7 : 20),
              ),
              border: Border.all(
                color: isMe
                    ? AppColors.primary.withValues(alpha: 0.18)
                    : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 7),
                bottomRight: Radius.circular(isMe ? 7 : 20),
              ),
              child: Container(
                color: bubbleColor,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
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
                        if (canReply || canShowActions)
                          _MessageActionsMenu(
                            canReply: canReply,
                            canEdit: canEdit,
                            canDelete: canDelete,
                            canReact: onReact != null && !isDeleted,
                            canForward: onForward != null && !isDeleted,
                            canTogglePin: onTogglePin != null && !isDeleted,
                            isPinned: pinned,
                            onReply: onReply,
                            onEdit: onEdit,
                            onDelete: onDelete,
                            onReact: onReact,
                            onForward: onForward,
                            onTogglePin: onTogglePin,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (hasReplyPreview) ...[
                      _ReplyPreview(
                        sender: replySenderLabel,
                        preview: replyPreview!.trim(),
                        isMine: isMe,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (forwarded && !isDeleted) ...[
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shortcut_rounded,
                            size: 14,
                            color: AppColors.muted,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                    ],
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
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              Image.network(
                                mediaUrl!,
                                width: double.infinity,
                                height: screenWidth >= 700 ? 240 : 200,
                                fit: BoxFit.cover,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;

                                      return Container(
                                        height: screenWidth >= 700 ? 240 : 200,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: AppColors.background,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.4,
                                              ),
                                            ),
                                            SizedBox(height: 10),
                                            Text(
                                              'Loading image',
                                              style: TextStyle(
                                                color: AppColors.muted,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    height: 150,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: const Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          color: AppColors.muted,
                                          size: 30,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'Could not load image',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
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
                      GestureDetector(
                        onTap: () => _openVideo(context),
                        child: _MediaFrame(
                          footer: _MediaMetaRow(
                            label: _fileMetaLabel,
                            onDownload: _openMediaExternally,
                          ),
                          child: VideoMessagePlayer(url: mediaUrl!),
                        ),
                      )
                    else if (isVoice)
                      _MediaFrame(
                        footer: _fileMetaLabel.isEmpty
                            ? null
                            : _MediaMetaRow(
                                label: _fileMetaLabel,
                                onDownload: _openMediaExternally,
                              ),
                        child: VoiceMessagePlayer(
                          url: mediaUrl!,
                          durationMs: durationMs,
                        ),
                      )
                    else if (isDocument)
                      _DocumentMessageCard(
                        fileName: fileName?.trim().isNotEmpty == true
                            ? fileName!.trim()
                            : 'Document',
                        metaLabel: _fileMetaLabel,
                        onOpen: _openMediaExternally,
                      )
                    else if (isMediaGroup)
                      _MediaGroupGrid(
                        attachments: groupAttachments,
                        onOpen: (attachment) =>
                            _openAttachment(context, attachment),
                      )
                    else
                      _LinkedMessageText(text: text),
                    if (time.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      if (_reactionCounts.isNotEmpty) ...[
                        _ReactionStrip(reactions: _reactionCounts),
                        const SizedBox(height: 7),
                      ],
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
                            if (deliveryStatus != null)
                              _DeliveryStatus(
                                icon: deliveryStatusIcon,
                                label: deliveryStatusLabel,
                                color: deliveryStatusColor,
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
      ),
    );
  }

  Map<String, int> get _reactionCounts {
    final input = reactions;
    if (input == null || input.isEmpty) return const {};

    final counts = <String, int>{};
    for (final entry in input.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        counts[entry.key] = value.length;
      }
    }
    return counts;
  }

  String get _fileMetaLabel {
    final parts = <String>[];
    final typeLabel = fileType?.trim();
    if (typeLabel != null && typeLabel.isNotEmpty) parts.add(typeLabel);
    if (fileSizeBytes != null && fileSizeBytes! > 0) {
      parts.add(_formatBytes(fileSizeBytes!));
    }
    return parts.join(' - ');
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _MediaGroupGrid extends StatelessWidget {
  final List<Map<String, dynamic>> attachments;
  final void Function(Map<String, dynamic> attachment) onOpen;

  const _MediaGroupGrid({required this.attachments, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final visibleAttachments = attachments.take(4).toList();
    final extraCount = attachments.length - visibleAttachments.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final totalWidth = constraints.maxWidth;
        final tileHeight = _gridHeight(visibleAttachments.length, totalWidth);

        return ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            width: totalWidth,
            height: tileHeight,
            child: _buildGrid(
              totalWidth: totalWidth,
              height: tileHeight,
              gap: gap,
              visibleAttachments: visibleAttachments,
              extraCount: extraCount,
            ),
          ),
        );
      },
    );
  }

  Widget _buildGrid({
    required double totalWidth,
    required double height,
    required double gap,
    required List<Map<String, dynamic>> visibleAttachments,
    required int extraCount,
  }) {
    if (visibleAttachments.length == 1) {
      return _tile(visibleAttachments[0], totalWidth, height, extraCount);
    }

    if (visibleAttachments.length == 2) {
      final tileWidth = (totalWidth - gap) / 2;
      return Row(
        children: [
          _tile(visibleAttachments[0], tileWidth, height, 0),
          SizedBox(width: gap),
          _tile(visibleAttachments[1], tileWidth, height, extraCount),
        ],
      );
    }

    if (visibleAttachments.length == 3) {
      final largeWidth = (totalWidth - gap) * 0.58;
      final sideWidth = totalWidth - largeWidth - gap;
      final sideHeight = (height - gap) / 2;
      return Row(
        children: [
          _tile(visibleAttachments[0], largeWidth, height, 0),
          SizedBox(width: gap),
          Column(
            children: [
              _tile(visibleAttachments[1], sideWidth, sideHeight, 0),
              SizedBox(height: gap),
              _tile(visibleAttachments[2], sideWidth, sideHeight, extraCount),
            ],
          ),
        ],
      );
    }

    final tileWidth = (totalWidth - gap) / 2;
    final tileHeight = (height - gap) / 2;
    return Column(
      children: [
        Row(
          children: [
            _tile(visibleAttachments[0], tileWidth, tileHeight, 0),
            SizedBox(width: gap),
            _tile(visibleAttachments[1], tileWidth, tileHeight, 0),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            _tile(visibleAttachments[2], tileWidth, tileHeight, 0),
            SizedBox(width: gap),
            _tile(visibleAttachments[3], tileWidth, tileHeight, extraCount),
          ],
        ),
      ],
    );
  }

  Widget _tile(
    Map<String, dynamic> attachment,
    double width,
    double height,
    int extraCount,
  ) {
    return _MediaGroupTile(
      attachment: attachment,
      width: width,
      height: height,
      extraCount: extraCount,
      onOpen: () => onOpen(attachment),
    );
  }

  double _gridHeight(int count, double width) {
    if (count <= 1) return (width * 0.58).clamp(180.0, 260.0);
    if (count == 2) return (width * 0.48).clamp(160.0, 230.0);
    return (width * 0.62).clamp(210.0, 310.0);
  }
}

class _MediaGroupTile extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final double width;
  final double height;
  final int extraCount;
  final VoidCallback onOpen;

  const _MediaGroupTile({
    required this.attachment,
    required this.width,
    required this.height,
    required this.extraCount,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final type = attachment['type']?.toString() ?? '';
    final url = attachment['media_url']?.toString() ?? '';
    final fileName = attachment['file_name']?.toString() ?? 'Media';
    final isVideo = type == 'video';

    return Material(
      color: const Color(0xFF0F172A),
      child: InkWell(
        onTap: onOpen,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!isVideo && url.isNotEmpty)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _MediaFallbackTile(
                    icon: Icons.broken_image_outlined,
                    label: fileName,
                  ),
                )
              else
                _MediaFallbackTile(
                  icon: isVideo
                      ? Icons.play_circle_fill_rounded
                      : Icons.photo_rounded,
                  label: fileName,
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.04),
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              if (isVideo)
                Center(
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              Positioned(
                left: 9,
                right: 9,
                bottom: 8,
                child: Row(
                  children: [
                    Icon(
                      isVideo ? Icons.videocam_rounded : Icons.image_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        isVideo ? 'Video' : 'Photo',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (extraCount > 0)
                Container(
                  color: Colors.black.withValues(alpha: 0.62),
                  alignment: Alignment.center,
                  child: Text(
                    '+$extraCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaFallbackTile extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MediaFallbackTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF111827), Color(0xFF020617)],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white70, size: 34),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedMessageText extends StatefulWidget {
  final String text;

  const _LinkedMessageText({required this.text});

  @override
  State<_LinkedMessageText> createState() => _LinkedMessageTextState();
}

class _LinkedMessageTextState extends State<_LinkedMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final links = _extractLinks(widget.text);
    final firstLink = links.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (firstLink != null) ...[
          _LinkPreviewCard(link: firstLink),
          const SizedBox(height: 9),
        ],
        SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 15.25,
              height: 1.45,
              color: AppColors.ink,
            ),
            children: _buildTextSpans(widget.text),
          ),
        ),
      ],
    );
  }

  List<InlineSpan> _buildTextSpans(String value) {
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in _linkPattern.allMatches(value)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }

      final rawUrl = match.group(0)!;
      final uri = _normalizeLink(rawUrl);
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (uri != null) {
            unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
          }
        };
      _recognizers.add(recognizer);

      spans.add(
        TextSpan(
          text: rawUrl,
          recognizer: recognizer,
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      cursor = match.end;
    }

    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }

    return spans.isEmpty ? [TextSpan(text: value)] : spans;
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final _MessageLink link;

  const _LinkPreviewCard({required this.link});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(
          launchUrl(link.uri, mode: LaunchMode.externalApplication),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.link_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      link.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      link.displayUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageLink {
  final Uri uri;
  final String raw;

  const _MessageLink({required this.uri, required this.raw});

  String get host => uri.host.replaceFirst(RegExp(r'^www\.'), '');

  String get displayUrl {
    final value = raw.trim();
    if (value.length <= 72) return value;
    return '${value.substring(0, 69)}...';
  }
}

final _linkPattern = RegExp(
  r'((?:https?:\/\/)?(?:www\.)?[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+(?:[^\s<>()]*)?)',
  caseSensitive: false,
);

List<_MessageLink> _extractLinks(String value) {
  return _linkPattern
      .allMatches(value)
      .map((match) {
        final raw = match.group(0) ?? '';
        final uri = _normalizeLink(raw);
        return uri == null ? null : _MessageLink(uri: uri, raw: raw);
      })
      .whereType<_MessageLink>()
      .toList();
}

Uri? _normalizeLink(String value) {
  final cleaned = value.trim().replaceAll(RegExp(r'[.,;:!?]+$'), '');
  if (cleaned.isEmpty) return null;

  final candidate =
      cleaned.startsWith(RegExp(r'https?:\/\/', caseSensitive: false))
      ? cleaned
      : 'https://$cleaned';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.trim().isEmpty || !uri.host.contains('.')) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;

  return uri;
}

class _MessageActionsMenu extends StatelessWidget {
  final bool canReply;
  final bool canEdit;
  final bool canDelete;
  final bool canReact;
  final bool canForward;
  final bool canTogglePin;
  final bool isPinned;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onForward;
  final VoidCallback? onTogglePin;

  const _MessageActionsMenu({
    required this.canReply,
    required this.canEdit,
    required this.canDelete,
    required this.canReact,
    required this.canForward,
    required this.canTogglePin,
    required this.isPinned,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onForward,
    required this.onTogglePin,
  });

  @override
  Widget build(BuildContext context) {
    if (!canReply &&
        !canEdit &&
        !canDelete &&
        !canReact &&
        !canForward &&
        !canTogglePin) {
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
          case _MessageAction.reply:
            onReply?.call();
            break;
          case _MessageAction.react:
            onReact?.call();
            break;
          case _MessageAction.forward:
            onForward?.call();
            break;
          case _MessageAction.pin:
            onTogglePin?.call();
            break;
          case _MessageAction.edit:
            onEdit?.call();
            break;
          case _MessageAction.delete:
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (canReply)
          const PopupMenuItem(
            value: _MessageAction.reply,
            child: _MessageActionRow(icon: Icons.reply_rounded, label: 'Reply'),
          ),
        if (canReact)
          const PopupMenuItem(
            value: _MessageAction.react,
            child: _MessageActionRow(
              icon: Icons.add_reaction_outlined,
              label: 'React',
            ),
          ),
        if (canForward)
          const PopupMenuItem(
            value: _MessageAction.forward,
            child: _MessageActionRow(
              icon: Icons.shortcut_rounded,
              label: 'Forward',
            ),
          ),
        if (canTogglePin)
          PopupMenuItem(
            value: _MessageAction.pin,
            child: _MessageActionRow(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              label: isPinned ? 'Unpin message' : 'Pin message',
            ),
          ),
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

enum _MessageAction { reply, react, forward, pin, edit, delete }

class _ReactionStrip extends StatelessWidget {
  final Map<String, int> reactions;

  const _ReactionStrip({required this.reactions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: reactions.entries
          .map(
            (entry) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '${entry.key} ${entry.value}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DocumentMessageCard extends StatelessWidget {
  final String fileName;
  final String metaLabel;
  final VoidCallback onOpen;

  const _DocumentMessageCard({
    required this.fileName,
    required this.metaLabel,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.16),
                      AppColors.accent.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13.5,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      metaLabel.isEmpty
                          ? 'Tap to open or download'
                          : '$metaLabel - tap to open or download',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.download_rounded,
                color: AppColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final String sender;
  final String preview;
  final bool isMine;

  const _ReplyPreview({
    required this.sender,
    required this.preview,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isMine ? AppColors.primary : AppColors.teacher;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isMine ? 0.58 : 0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryStatus extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _DeliveryStatus({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MediaFrame extends StatelessWidget {
  final Widget child;
  final Widget? footer;

  const _MediaFrame({required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

class _MediaMetaRow extends StatelessWidget {
  final String label;
  final VoidCallback onDownload;

  const _MediaMetaRow({required this.label, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label.isEmpty ? 'Media attachment' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded),
          iconSize: 18,
          tooltip: 'Open or download',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
