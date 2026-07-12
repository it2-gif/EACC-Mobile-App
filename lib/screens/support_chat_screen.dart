import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/auth_session.dart';
import '../services/support_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/polished_state_card.dart';

class SupportInboxScreen extends StatelessWidget {
  final AuthSession session;

  const SupportInboxScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Technical Support'),
        shape: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: SupportChatService.getSupportThreads(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _SupportState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load support chats',
                    subtitle: '${snapshot.error}',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: PolishedLoadingCard(
                      title: 'Loading support inbox',
                      message: 'Checking the latest live-help conversations.',
                    ),
                  );
                }

                final threads = snapshot.data?.docs ?? [];
                if (threads.isEmpty) {
                  return const _SupportState(
                    icon: Icons.support_agent_rounded,
                    title: 'No support requests yet',
                    subtitle: 'New conversations will appear here.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: threads.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _SupportInboxHeader(total: threads.length);
                    }

                    final doc = threads[index - 1];
                    final data = doc.data();
                    final requesterName =
                        data['requester_name']?.toString().trim() ?? 'User';
                    final requesterRole =
                        data['requester_role']?.toString().trim() ?? 'user';
                    final unread =
                        (data['support_unread_count'] as num?)?.toInt() ?? 0;

                    return _SupportThreadTile(
                      title: requesterName.isEmpty ? 'User' : requesterName,
                      subtitle:
                          data['last_message']?.toString() ?? 'No messages yet',
                      meta:
                          '${requesterRole.toUpperCase()} - ${formatThreadTime(data['last_message_at'] ?? data['updated_at'])}',
                      unread: unread,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SupportChatScreen(
                            session: session,
                            threadId: doc.id,
                            requesterName: requesterName,
                            requesterRole: requesterRole,
                            requesterLmsUserId: data['requester_lms_user_id']
                                ?.toString(),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class SupportChatScreen extends StatefulWidget {
  final AuthSession session;
  final String? threadId;
  final String? requesterName;
  final String? requesterRole;
  final String? requesterLmsUserId;

  const SupportChatScreen({
    super.key,
    required this.session,
    this.threadId,
    this.requesterName,
    this.requesterRole,
    this.requesterLmsUserId,
  });

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final messageController = TextEditingController();
  final scrollController = ScrollController();
  bool isSending = false;
  bool isUploadingImage = false;
  double uploadProgress = 0;

  late final String threadId =
      widget.threadId ?? SupportChatService.threadIdFor(widget.session);

  bool get isSupportUser => widget.session.appUser.isTechnicalSupport;

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || isSending) return;

    setState(() => isSending = true);
    messageController.clear();

    try {
      await SupportChatService.sendMessage(
        session: widget.session,
        threadId: threadId,
        text: text,
        requesterName: widget.requesterName,
        requesterRole: widget.requesterRole,
        requesterLmsUserId: widget.requesterLmsUserId,
      );
      scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send support message: $error')),
      );
      messageController.text = text;
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  Future<void> pickAndSendImage() async {
    if (isSending || isUploadingImage) return;

    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image == null) return;

    setState(() {
      isUploadingImage = true;
      uploadProgress = 0;
    });

    try {
      final imageBytes = await image.readAsBytes();
      await SupportChatService.sendImageMessage(
        session: widget.session,
        threadId: threadId,
        imageBytes: imageBytes,
        fileName: image.name,
        requesterName: widget.requesterName,
        requesterRole: widget.requesterRole,
        requesterLmsUserId: widget.requesterLmsUserId,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => uploadProgress = progress);
        },
      );
      scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not upload image: $error')));
    } finally {
      if (mounted) {
        setState(() {
          isUploadingImage = false;
          uploadProgress = 0;
        });
      }
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = isSupportUser
        ? (widget.requesterName?.trim().isNotEmpty == true
              ? widget.requesterName!.trim()
              : 'Support request')
        : 'Technical Support';

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        toolbarHeight: 72,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.support_agent_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSupportUser
                        ? 'Technical support inbox'
                        : 'Ask us anything. We will reply here.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: SupportChatService.getMessages(threadId: threadId),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _SupportState(
                          icon: Icons.error_outline_rounded,
                          title: 'Could not load messages',
                          subtitle: '${snapshot.error}',
                        );
                      }

                      final docs = snapshot.data?.docs ?? [];
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: PolishedLoadingCard(
                            title: 'Loading support chat',
                            message: 'Preparing your support conversation.',
                          ),
                        );
                      }

                      if (docs.isEmpty) {
                        return const _SupportState(
                          icon: Icons.support_agent_rounded,
                          title: 'How can we help?',
                          subtitle:
                              'Send a message and technical support will reply here.',
                        );
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        unawaited(
                          SupportChatService.markRead(
                            session: widget.session,
                            threadId: threadId,
                          ),
                        );
                      });

                      return ListView.builder(
                        controller: scrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final data = docs[index].data();
                          final senderName =
                              data['sender_name']?.toString() ?? '';
                          final senderRole =
                              data['sender_role']?.toString() ?? '';
                          final isMine =
                              senderName == widget.session.appUser.name &&
                              (senderRole == widget.session.appUser.role ||
                                  senderRole == 'support');

                          return _SupportMessageBubble(
                            text: data['text']?.toString() ?? '',
                            type: data['type']?.toString() ?? 'text',
                            mediaUrl: data['media_url']?.toString(),
                            fileName: data['file_name']?.toString(),
                            senderName: senderName,
                            senderRole: senderRole,
                            time: formatMessageTime(data['created_at']),
                            isMine: isMine,
                          );
                        },
                      );
                    },
                  ),
                ),
                _SupportInputBar(
                  controller: messageController,
                  isSending: isSending || isUploadingImage,
                  uploadProgress: isUploadingImage ? uploadProgress : null,
                  onPickImage: pickAndSendImage,
                  onSend: sendMessage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportThreadTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String meta;
  final int unread;
  final VoidCallback onTap;

  const _SupportThreadTile({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      AppColors.accent.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Center(
                  child: Text(
                    title.trim().isEmpty ? '?' : title.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (unread > 0) _AnimatedUnreadBadge(unread: unread),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      meta,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primaryDark,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportInboxHeader extends StatelessWidget {
  final int total;

  const _SupportInboxHeader({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(Icons.support_agent_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Help Inbox',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$total active support conversation${total == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w700,
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

class _AnimatedUnreadBadge extends StatelessWidget {
  final int unread;

  const _AnimatedUnreadBadge({required this.unread});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Text(
          unread > 99 ? '99+' : '$unread',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _SupportMessageBubble extends StatelessWidget {
  final String text;
  final String type;
  final String? mediaUrl;
  final String? fileName;
  final String senderName;
  final String senderRole;
  final String time;
  final bool isMine;

  const _SupportMessageBubble({
    required this.text,
    required this.type,
    this.mediaUrl,
    this.fileName,
    required this.senderName,
    required this.senderRole,
    required this.time,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final color = isMine ? AppColors.primary : Colors.white;
    final textColor = isMine ? Colors.white : AppColors.ink;
    final isImage = type == 'image' && mediaUrl != null && mediaUrl!.isNotEmpty;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: Radius.circular(isMine ? 6 : 20),
            bottomLeft: Radius.circular(isMine ? 20 : 6),
          ),
          border: isMine ? null : Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  senderRole == 'support' ? 'Technical Support' : senderName,
                  style: TextStyle(
                    color: isMine ? Colors.white70 : AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (isImage) ...[
              _SupportImagePreview(
                url: mediaUrl!,
                fileName: fileName,
                isMine: isMine,
              ),
              if (text.trim().isNotEmpty) const SizedBox(height: 8),
            ],
            if (text.trim().isNotEmpty)
              Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14.5,
                  height: 1.35,
                ),
              ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  time,
                  style: TextStyle(
                    color: isMine ? Colors.white70 : AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupportImagePreview extends StatelessWidget {
  final String url;
  final String? fileName;
  final bool isMine;

  const _SupportImagePreview({
    required this.url,
    required this.fileName,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: Stack(
            children: [
              InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 260, minWidth: 220),
          color: isMine
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.background,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const SizedBox(
                height: 180,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.3),
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
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) => SizedBox(
              height: 140,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      color: isMine ? Colors.white70 : AppColors.muted,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      fileName ?? 'Could not load image',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isMine ? Colors.white : AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final double? uploadProgress;
  final VoidCallback onPickImage;
  final VoidCallback onSend;

  const _SupportInputBar({
    required this.controller,
    required this.isSending,
    required this.uploadProgress,
    required this.onPickImage,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (uploadProgress != null) ...[
              LinearProgressIndicator(
                value: uploadProgress == 0 ? null : uploadProgress,
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: isSending ? null : onPickImage,
                  icon: const Icon(Icons.image_rounded),
                  tooltip: 'Upload image',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Write your support message',
                        prefixIcon: Icon(Icons.edit_note_rounded),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: isSending ? null : onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(50, 50),
                    padding: EdgeInsets.zero,
                  ),
                  child: isSending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SupportState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: PolishedStateCard(
        icon: icon,
        title: title,
        message: subtitle,
        color: icon == Icons.error_outline_rounded
            ? AppColors.danger
            : AppColors.primary,
      ),
    );
  }
}
