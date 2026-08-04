import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../services/chat_thread_resolver.dart';
import '../services/firestore_chat_service.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final String currentUserRole;
  final String courseId;
  final String threadId;
  final String senderName;
  final String? threadStudentName;
  final bool isSuperAdmin;
  final bool canManageAllMessages;
  final bool readOnly;

  const ChatScreen({
    super.key,
    required this.title,
    required this.currentUserRole,
    required this.courseId,
    required this.threadId,
    required this.senderName,
    this.threadStudentName,
    this.isSuperAdmin = false,
    this.canManageAllMessages = false,
    this.readOnly = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int messagesPerPage = 30;
  static final NotificationApi _notificationApi = NotificationApi();

  final messageController = TextEditingController();
  final searchController = TextEditingController();
  final scrollController = ScrollController();
  final audioRecorder = AudioRecorder();
  final voiceChunks = <Uint8List>[];

  bool isSending = false;
  bool isUploadingMedia = false;
  bool isRecordingVoice = false;
  bool isVoiceRecordingPaused = false;
  bool isLoadingOlderMessages = false;
  bool isOlderPositionRestoreScheduled = false;
  bool shouldScrollAfterSending = false;
  bool hasScrolledToInitialBottom = false;
  bool hasScheduledInitialBottomScroll = false;
  bool isInitialChatReady = false;
  int messageLimit = messagesPerPage;
  String? latestMessageId;
  double scrollOffsetBeforeLoadingOlder = 0;
  double scrollExtentBeforeLoadingOlder = 0;
  Duration recordingDuration = Duration.zero;
  Timer? recordingTimer;
  StreamSubscription<Uint8List>? recordingSubscription;
  int recordingSampleRate = 16000;
  double? mediaUploadProgress;
  String? mediaUploadLabel;
  _PendingAttachment? failedAttachment;
  MessageReply? selectedReply;
  bool isSearchingMessages = false;
  String messageSearchQuery = '';
  Timer? typingStopTimer;
  bool typingStateSent = false;
  int? lastScheduledAnnouncementReadAt;

  bool get isAnnouncementThread =>
      widget.threadId == ChatThreadResolver.announcementThreadId;

  bool get isAdminTeacherThread =>
      widget.threadId == ChatThreadResolver.adminTeacherThreadId;

  bool get isKeyPersonStudentThread =>
      ChatThreadResolver.isStudentContactPersonThreadId(widget.threadId);

  bool get canSendInThread =>
      !widget.readOnly &&
      (!isAnnouncementThread || widget.currentUserRole != 'student');

  @override
  void dispose() {
    typingStopTimer?.cancel();
    messageController.removeListener(handleTypingChanged);
    if (typingStateSent) {
      unawaited(setTypingState(false));
    }
    recordingTimer?.cancel();
    recordingSubscription?.cancel();
    audioRecorder.dispose();
    messageController.dispose();
    searchController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    messageController.addListener(handleTypingChanged);
    if (!isAnnouncementThread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(markThreadAsRead());
      });
    }
  }

  void handleTypingChanged() {
    if (!canSendInThread || isRecordingVoice) return;

    final isTyping = messageController.text.trim().isNotEmpty;
    if (isTyping && !typingStateSent) {
      typingStateSent = true;
      unawaited(setTypingState(true));
    }

    typingStopTimer?.cancel();
    if (isTyping) {
      typingStopTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        typingStateSent = false;
        unawaited(setTypingState(false));
      });
    } else if (typingStateSent) {
      typingStateSent = false;
      unawaited(setTypingState(false));
    }
  }

  Future<void> setTypingState(bool isTyping) {
    return FirestoreChatService.setTypingState(
      courseId: widget.courseId,
      threadId: widget.threadId,
      senderRole: widget.currentUserRole,
      senderName: widget.senderName,
      isTyping: isTyping,
    ).catchError((_) {});
  }

  Future<void> logAuditEvent({
    required String action,
    required String resourceType,
    required String resourceId,
    Map<String, dynamic>? metadata,
  }) {
    return FirestoreChatService.logAuditEvent(
      actorRole: widget.currentUserRole,
      actorName: widget.senderName,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      metadata: {
        'course_id': widget.courseId,
        'thread_id': widget.threadId,
        ...?metadata,
      },
    ).catchError((_) {});
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToBottomIfPossible(animate: true);
    });
  }

  void _jumpToBottomIfPossible({required bool animate}) {
    if (!mounted || !scrollController.hasClients) return;

    final targetOffset = scrollController.position.minScrollExtent;
    if (animate) {
      scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    scrollController.jumpTo(targetOffset);
  }

  Future<void> scheduleInitialBottomScroll() async {
    if (hasScheduledInitialBottomScroll) return;
    hasScheduledInitialBottomScroll = true;

    var stableFrames = 0;
    var previousMaxExtent = -1.0;

    // A builder-backed list can refine its scroll extent over several frames,
    // especially on web. Keep following the extent until it settles.
    for (var attempt = 0; attempt < 16 && stableFrames < 3; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      if (!scrollController.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        continue;
      }

      final maxExtent = scrollController.position.maxScrollExtent;
      scrollController.jumpTo(scrollController.position.minScrollExtent);

      if ((maxExtent - previousMaxExtent).abs() < 0.5) {
        stableFrames++;
      } else {
        stableFrames = 0;
        previousMaxExtent = maxExtent;
      }
    }

    if (!mounted) return;
    _jumpToBottomIfPossible(animate: false);
    setState(() {
      isInitialChatReady = true;
    });
  }

  Future<void> markThreadAsRead() async {
    if (isAnnouncementThread) {
      if (widget.currentUserRole != 'student') return;
      try {
        await FirestoreChatService.markAnnouncementRead(
          courseId: widget.courseId,
          readerRole: widget.currentUserRole,
          readerName: widget.senderName,
        );
      } catch (error) {
        debugPrint('Could not mark announcement as read: $error');
      }
      return;
    }

    if (widget.currentUserRole == 'admin' &&
        !isAdminTeacherThread &&
        !isKeyPersonStudentThread) {
      return;
    }

    try {
      await FirestoreChatService.markThreadRead(
        courseId: widget.courseId,
        threadId: widget.threadId,
        readerRole: widget.currentUserRole,
        studentName: _resolvedStudentName,
      );
    } catch (_) {}
  }

  void scheduleAnnouncementRead(Map<String, dynamic>? threadData) {
    if (!isAnnouncementThread || widget.currentUserRole != 'student') return;

    final lastMessageAt = threadData?['last_message_at'];
    if (lastMessageAt is! Timestamp) return;

    final marker = lastMessageAt.toDate().microsecondsSinceEpoch;
    if (lastScheduledAnnouncementReadAt == marker) return;
    lastScheduledAnnouncementReadAt = marker;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(markThreadAsRead());
    });
  }

  void loadOlderMessages() {
    if (isLoadingOlderMessages || !scrollController.hasClients) return;

    scrollOffsetBeforeLoadingOlder = scrollController.offset;
    scrollExtentBeforeLoadingOlder = scrollController.position.maxScrollExtent;

    setState(() {
      isLoadingOlderMessages = true;
      messageLimit += messagesPerPage;
    });
  }

  void restorePositionAfterLoadingOlderMessages() {
    if (!isLoadingOlderMessages || isOlderPositionRestoreScheduled) return;

    isOlderPositionRestoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;

      final addedScrollExtent =
          scrollController.position.maxScrollExtent -
          scrollExtentBeforeLoadingOlder;
      scrollController.jumpTo(
        (scrollOffsetBeforeLoadingOlder + addedScrollExtent).clamp(
          0,
          scrollController.position.maxScrollExtent,
        ),
      );

      setState(() {
        isLoadingOlderMessages = false;
        isOlderPositionRestoreScheduled = false;
      });
    });
  }

  void showAttachmentOptions() {
    if (!canSendInThread) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.photo_camera,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text('Take photo'),
                  subtitle: const Text('Capture and send immediately'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.videocam, color: AppColors.primary),
                  ),
                  title: const Text('Take video'),
                  subtitle: const Text('Record and send immediately'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendVideo(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.photo_library_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text('Choose images'),
                  subtitle: const Text('Select one or more photos'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.video_library_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text('Choose videos'),
                  subtitle: const Text('Select one or more videos'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendVideo(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.description_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text('Upload documents'),
                  subtitle: const Text(
                    'Select one or more PDF, Word, Excel, TXT, or CSV files',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendDocument();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> toggleVoiceRecording() async {
    if (!canSendInThread || isSending || isUploadingMedia) return;
    if (isRecordingVoice) {
      await stopAndSendVoiceMessage();
    } else {
      await startVoiceRecording();
    }
  }

  Future<void> startVoiceRecording() async {
    try {
      if (!await audioRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
        }
        return;
      }

      voiceChunks.clear();
      recordingSampleRate = 16000;
      await audioRecorder.setOnConfigChanged((config) {
        recordingSampleRate = config.sampleRate;
      });
      final stream = await audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      recordingSubscription = stream.listen(voiceChunks.add);
      recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (isVoiceRecordingPaused) return;
        setState(() {
          recordingDuration += const Duration(seconds: 1);
        });
        if (recordingDuration >= const Duration(minutes: 5)) {
          unawaited(stopAndSendVoiceMessage());
        }
      });

      if (mounted) {
        setState(() {
          recordingDuration = Duration.zero;
          isRecordingVoice = true;
          isVoiceRecordingPaused = false;
        });
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().toLowerCase();
        final isPermissionError =
            message.contains('permission') ||
            message.contains('notallowed') ||
            message.contains('not allowed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPermissionError
                  ? 'Microphone access is blocked. Allow it in the browser address bar, then try again.'
                  : 'Could not start voice recording: $error',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> stopAndSendVoiceMessage() async {
    final subscription = recordingSubscription;
    final streamDone = subscription?.asFuture<void>();
    recordingTimer?.cancel();

    if (mounted) {
      setState(() {
        isRecordingVoice = false;
        isVoiceRecordingPaused = false;
        isUploadingMedia = true;
      });
    }

    try {
      await audioRecorder.stop();
      await streamDone;
      recordingSubscription = null;

      final bytesBuilder = BytesBuilder(copy: false);
      for (final chunk in voiceChunks) {
        bytesBuilder.add(chunk);
      }
      final voiceBytes = _createWavFile(
        bytesBuilder.takeBytes(),
        sampleRate: recordingSampleRate,
        channels: 1,
        bitsPerSample: 16,
      );
      if (!_containsAudibleAudio(voiceBytes)) {
        throw const ChatUploadException(
          'No voice was detected. Check the selected microphone and try again.',
        );
      }
      FirestoreChatService.validateVoiceUpload(
        fileName: 'voice_message.wav',
        fileSize: voiceBytes.length,
      );
      shouldScrollAfterSending = true;
      await _sendVoiceAttachment(
        voiceBytes: voiceBytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
        durationMs: recordingDuration.inMilliseconds,
      );
    } on ChatUploadException catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $error')),
        );
      }
    } finally {
      voiceChunks.clear();
      if (mounted) {
        setState(() {
          isUploadingMedia = false;
          recordingDuration = Duration.zero;
          isVoiceRecordingPaused = false;
        });
      }
    }
  }

  Future<void> toggleVoiceRecordingPause() async {
    if (!isRecordingVoice) return;

    try {
      if (isVoiceRecordingPaused) {
        await audioRecorder.resume();
      } else {
        await audioRecorder.pause();
      }

      if (mounted) {
        setState(() => isVoiceRecordingPaused = !isVoiceRecordingPaused);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update recording: $error')),
      );
    }
  }

  Future<void> cancelVoiceRecording() async {
    recordingTimer?.cancel();
    try {
      await audioRecorder.cancel();
      await recordingSubscription?.cancel();
    } finally {
      recordingSubscription = null;
      voiceChunks.clear();
      if (mounted) {
        setState(() {
          isRecordingVoice = false;
          isVoiceRecordingPaused = false;
          recordingDuration = Duration.zero;
        });
      }
    }
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();

    if (!canSendInThread ||
        text.isEmpty ||
        isSending ||
        isUploadingMedia ||
        isRecordingVoice) {
      return;
    }

    messageController.clear();
    typingStopTimer?.cancel();
    typingStateSent = false;
    unawaited(setTypingState(false));
    final reply = selectedReply;

    setState(() {
      isSending = true;
      shouldScrollAfterSending = true;
      selectedReply = null;
    });

    try {
      final messageId = await FirestoreChatService.sendTextMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        text: text,
        studentName: _resolvedStudentName,
        reply: reply,
      );
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'text',
          previewText: text,
        ),
      );
    } catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        setState(() {
          selectedReply = reply;
        });
      }
      await _logFirestoreSendDebug(error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $error')),
        );
      }
    }

    if (mounted) setState(() => isSending = false);
  }

  Future<void> editMessage({
    required String messageId,
    required String currentText,
  }) async {
    final editController = TextEditingController(text: currentText);

    final updatedText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: editController,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Update your message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    editController.dispose();

    if (updatedText == null ||
        updatedText.isEmpty ||
        updatedText == currentText.trim()) {
      return;
    }

    try {
      await FirestoreChatService.editTextMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        messageId: messageId,
        text: updatedText,
      );
      unawaited(
        logAuditEvent(
          action: 'message_edited',
          resourceType: 'message',
          resourceId: messageId,
          metadata: {
            'preview': updatedText,
            'previous_text': currentText.trim(),
            'course_id': widget.courseId,
            'thread_id': widget.threadId,
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit message: $error')),
        );
      }
    }
  }

  Future<void> deleteMessage({
    required String messageId,
    required Map<String, dynamic> data,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This will remove the message content from this conversation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirestoreChatService.deleteMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        messageId: messageId,
        deletedByRole: widget.currentUserRole,
        deletedByName: widget.senderName,
      );
      unawaited(
        logAuditEvent(
          action: 'message_deleted',
          resourceType: 'message',
          resourceId: messageId,
          metadata: {
            'preview': _messagePreview(data),
            'sender_name': data['sender_name']?.toString() ?? '',
            'sender_role': data['sender_role']?.toString() ?? '',
            'course_id': widget.courseId,
            'thread_id': widget.threadId,
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $error')),
        );
      }
    }
  }

  void replyToMessage({
    required String messageId,
    required Map<String, dynamic> data,
  }) {
    if (!canSendInThread || data['deleted_at'] != null) return;

    setState(() {
      selectedReply = MessageReply(
        messageId: messageId,
        senderName: data['sender_name']?.toString() ?? 'Message',
        senderRole: data['sender_role']?.toString() ?? '',
        type: data['type']?.toString() ?? 'text',
        preview: _messagePreview(data),
      );
    });
  }

  void cancelReply() {
    if (selectedReply == null) return;
    setState(() => selectedReply = null);
  }

  bool get canForwardMessages =>
      !widget.readOnly &&
      (widget.currentUserRole == 'teacher' ||
          widget.currentUserRole == 'admin');

  bool get canPinMessages =>
      !widget.readOnly &&
      (widget.currentUserRole == 'teacher' ||
          widget.currentUserRole == 'admin');

  void toggleMessageSearch() {
    setState(() {
      isSearchingMessages = !isSearchingMessages;
      if (!isSearchingMessages) {
        messageSearchQuery = '';
        searchController.clear();
      }
    });
  }

  Future<void> reactToMessage(String messageId) async {
    if (widget.readOnly) return;

    const emojis = ['👍', '❤️', '✅', '👏', '🙏'];

    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: emojis
                .map(
                  (emoji) => InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.pop(context, emoji),
                    child: Container(
                      width: 56,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(emoji, style: const TextStyle(fontSize: 25)),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );

    if (emoji == null) return;

    try {
      await FirestoreChatService.toggleReaction(
        courseId: widget.courseId,
        threadId: widget.threadId,
        messageId: messageId,
        emoji: emoji,
        reactorRole: widget.currentUserRole,
        reactorName: widget.senderName,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to react: $error')));
    }
  }

  Future<void> togglePinMessage({
    required String messageId,
    required bool currentlyPinned,
    required Map<String, dynamic> data,
  }) async {
    if (!canPinMessages) return;

    try {
      await FirestoreChatService.setMessagePinned(
        courseId: widget.courseId,
        threadId: widget.threadId,
        messageId: messageId,
        pinned: !currentlyPinned,
        pinnedByRole: widget.currentUserRole,
        pinnedByName: widget.senderName,
      );
      unawaited(
        logAuditEvent(
          action: currentlyPinned ? 'message_unpinned' : 'message_pinned',
          resourceType: 'message',
          resourceId: messageId,
          metadata: {
            'preview': _messagePreview(data),
            'course_id': widget.courseId,
            'thread_id': widget.threadId,
          },
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update pinned message: $error')),
      );
    }
  }

  Future<void> forwardMessage({required Map<String, dynamic> data}) async {
    if (!canForwardMessages || data['deleted_at'] != null) return;

    final snapshot = await FirestoreChatService.getThreads(
      courseId: widget.courseId,
    ).first;
    if (!mounted) return;

    final destinations = snapshot.docs
        .where((doc) => doc.id != widget.threadId)
        .map((doc) {
          final data = doc.data();
          return _ForwardDestination(
            threadId: doc.id,
            title: data['title']?.toString().trim().isNotEmpty == true
                ? data['title'].toString().trim()
                : data['student_name']?.toString().trim().isNotEmpty == true
                ? data['student_name'].toString().trim()
                : doc.id,
            studentName: data['student_name']?.toString(),
          );
        })
        .toList();

    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No other chats available to forward to.'),
        ),
      );
      return;
    }

    final destination = await showModalBottomSheet<_ForwardDestination>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
          itemCount: destinations.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 4, 14),
                child: Text(
                  'Forward to',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              );
            }

            final destination = destinations[index - 1];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.shortcut_rounded,
                  color: AppColors.primary,
                ),
              ),
              title: Text(
                destination.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('Course ${widget.courseId}'),
              onTap: () => Navigator.pop(context, destination),
            );
          },
        ),
      ),
    );

    if (destination == null) return;

    try {
      final messageId = await FirestoreChatService.forwardMessage(
        courseId: widget.courseId,
        targetThreadId: destination.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        sourceData: data,
        studentName: destination.studentName,
      );
      unawaited(
        _notificationApi.notifyChatMessage(
          courseId: widget.courseId,
          threadId: destination.threadId,
          senderRole: widget.currentUserRole,
          senderName: widget.senderName,
          messageType: data['type']?.toString() ?? 'text',
          messageId: messageId,
          previewText: _messagePreview(data),
          studentName: destination.studentName,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Forwarded to ${destination.title}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to forward message: $error')),
      );
    }
  }

  Future<void> pickAndSendImage(ImageSource source) async {
    if (isUploadingMedia || isSending || isRecordingVoice) return;

    final picker = ImagePicker();
    final images = <XFile>[];
    if (source == ImageSource.gallery) {
      images.addAll(
        await picker.pickMultiImage(
          imageQuality: 78,
          maxWidth: 1920,
          maxHeight: 1920,
        ),
      );
    } else {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image != null) images.add(image);
    }

    if (images.isEmpty) return;

    final reply = selectedReply;
    if (images.length > 1) {
      await _sendMediaGroupAttachment(
        items: await _readMediaGroupItems(images, type: 'image'),
        reply: reply,
      );
      return;
    }

    final image = images.single;
    try {
      final imageSize = await image.length();
      FirestoreChatService.validateImageUpload(
        fileName: image.name,
        fileSize: imageSize,
      );

      final imageBytes = await image.readAsBytes();
      shouldScrollAfterSending = true;

      await _sendImageAttachment(
        imageBytes: imageBytes,
        fileName: image.name,
        reply: reply,
      );
    } on ChatUploadException catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      shouldScrollAfterSending = false;
      _showImageUploadError(error);
    }
  }

  Future<void> pickAndSendVideo(ImageSource source) async {
    if (isUploadingMedia || isSending || isRecordingVoice) return;

    final reply = selectedReply;
    if (source == ImageSource.gallery) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            FirestoreChatService.supportedVideoExtensions.toList()..sort(),
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final items = <ChatMediaUploadItem>[];
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not read ${file.name}.')),
          );
          return;
        }
        FirestoreChatService.validateVideoUpload(
          fileName: file.name,
          fileSize: bytes.length,
        );
        items.add(
          ChatMediaUploadItem(bytes: bytes, fileName: file.name, type: 'video'),
        );
      }

      if (items.length > 1) {
        await _sendMediaGroupAttachment(items: items, reply: reply);
      } else {
        final item = items.single;
        await _sendVideoAttachment(
          videoBytes: item.bytes,
          fileName: item.fileName,
          reply: reply,
        );
      }
      return;
    }

    final video = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 2),
    );
    if (video == null) return;

    try {
      final videoSize = await video.length();
      FirestoreChatService.validateVideoUpload(
        fileName: video.name,
        fileSize: videoSize,
      );
      final videoBytes = await video.readAsBytes();
      shouldScrollAfterSending = true;

      await _sendVideoAttachment(
        videoBytes: videoBytes,
        fileName: video.name,
        reply: reply,
      );
    } on ChatUploadException catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      shouldScrollAfterSending = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload video: $error')),
        );
      }
    }
  }

  Future<void> pickAndSendDocument() async {
    if (isUploadingMedia || isSending || isRecordingVoice) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          FirestoreChatService.supportedDocumentExtensions.toList()..sort(),
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final reply = selectedReply;
    for (var index = 0; index < result.files.length; index += 1) {
      final file = result.files[index];
      final documentBytes = file.bytes;
      if (documentBytes == null || documentBytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not read ${file.name}.')));
        break;
      }

      try {
        FirestoreChatService.validateDocumentUpload(
          fileName: file.name,
          fileSize: documentBytes.length,
        );
        shouldScrollAfterSending = true;
        await _sendDocumentAttachment(
          documentBytes: documentBytes,
          fileName: file.name,
          reply: reply,
          uploadLabel: result.files.length == 1
              ? null
              : 'Uploading document ${index + 1} of ${result.files.length}...',
        );
        if (failedAttachment != null) break;
      } on ChatUploadException catch (error) {
        shouldScrollAfterSending = false;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.message)));
        }
        break;
      } catch (error) {
        shouldScrollAfterSending = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload document: $error')),
          );
        }
        break;
      }
    }
  }

  Future<List<ChatMediaUploadItem>> _readMediaGroupItems(
    List<XFile> files, {
    required String type,
  }) async {
    final items = <ChatMediaUploadItem>[];
    for (final file in files) {
      final size = await file.length();
      if (type == 'image') {
        FirestoreChatService.validateImageUpload(
          fileName: file.name,
          fileSize: size,
        );
      } else {
        FirestoreChatService.validateVideoUpload(
          fileName: file.name,
          fileSize: size,
        );
      }
      items.add(
        ChatMediaUploadItem(
          bytes: await file.readAsBytes(),
          fileName: file.name,
          type: type,
        ),
      );
    }
    return items;
  }

  void _showImageUploadError(Object error) {
    if (!mounted) return;
    final message = error.toString().toLowerCase();
    final isCors =
        message.contains('cors') || message.contains('xmlhttprequest');
    final isStorage =
        message.contains('storage') || message.contains('unauthorized');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCors
              ? 'Storage upload is not ready. Enable Firebase Storage, then apply CORS from scripts/SETUP.md.'
              : isStorage
              ? 'Firebase Storage not ready. Enable Storage in Firebase Console first.'
              : 'Failed to upload image: $error',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> retryLastAttachment() async {
    final attachment = failedAttachment;
    if (attachment == null) return;

    setState(() {
      failedAttachment = null;
    });

    switch (attachment.kind) {
      case _AttachmentKind.image:
        await _sendImageAttachment(
          imageBytes: attachment.bytes,
          fileName: attachment.fileName,
          reply: attachment.reply,
          retrying: true,
        );
        break;
      case _AttachmentKind.video:
        await _sendVideoAttachment(
          videoBytes: attachment.bytes,
          fileName: attachment.fileName,
          reply: attachment.reply,
          retrying: true,
        );
        break;
      case _AttachmentKind.voice:
        await _sendVoiceAttachment(
          voiceBytes: attachment.bytes,
          fileName: attachment.fileName,
          durationMs: attachment.durationMs ?? 0,
          reply: attachment.reply,
          retrying: true,
        );
        break;
      case _AttachmentKind.document:
        await _sendDocumentAttachment(
          documentBytes: attachment.bytes,
          fileName: attachment.fileName,
          reply: attachment.reply,
          retrying: true,
        );
        break;
    }
  }

  Future<void> _sendMediaGroupAttachment({
    required List<ChatMediaUploadItem> items,
    MessageReply? reply,
    bool retrying = false,
  }) async {
    final effectiveReply = reply ?? selectedReply;
    final imageCount = items.where((item) => item.type == 'image').length;
    final videoCount = items.where((item) => item.type == 'video').length;
    final label = imageCount > 0 && videoCount > 0
        ? '${items.length} media files'
        : imageCount > 0
        ? '$imageCount photos'
        : '$videoCount videos';

    _beginMediaUpload(retrying ? 'Retrying $label...' : 'Uploading $label...');
    try {
      final messageId = await FirestoreChatService.sendMediaGroupMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        items: items,
        studentName: _resolvedStudentName,
        reply: effectiveReply,
        onProgress: _updateMediaUploadProgress,
      );
      if (mounted) setState(() => selectedReply = null);
      shouldScrollAfterSending = true;
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'media_group',
          previewText: label,
        ),
      );
      _clearMediaUploadState();
    } catch (error) {
      _clearMediaUploadState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload $label: $error')),
      );
    }
  }

  Future<void> _sendImageAttachment({
    required Uint8List imageBytes,
    required String fileName,
    MessageReply? reply,
    bool retrying = false,
    String? uploadLabel,
  }) async {
    final effectiveReply = reply ?? selectedReply;
    _beginMediaUpload(
      uploadLabel ?? (retrying ? 'Retrying photo...' : 'Uploading photo...'),
    );
    try {
      final messageId = await FirestoreChatService.sendImageMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        imageBytes: imageBytes,
        fileName: fileName,
        studentName: _resolvedStudentName,
        reply: effectiveReply,
        onProgress: _updateMediaUploadProgress,
      );
      if (mounted) setState(() => selectedReply = null);
      shouldScrollAfterSending = true;
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'image',
          previewText: 'Photo',
        ),
      );
      _clearMediaUploadState();
    } catch (error) {
      _failMediaUpload(
        _PendingAttachment(
          kind: _AttachmentKind.image,
          fileName: fileName,
          bytes: imageBytes,
          reply: effectiveReply,
        ),
      );
      _showUploadFailure(error, 'Failed to upload image');
    }
  }

  Future<void> _sendVideoAttachment({
    required Uint8List videoBytes,
    required String fileName,
    MessageReply? reply,
    bool retrying = false,
  }) async {
    final effectiveReply = reply ?? selectedReply;
    _beginMediaUpload(retrying ? 'Retrying video...' : 'Uploading video...');
    try {
      final messageId = await FirestoreChatService.sendVideoMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        videoBytes: videoBytes,
        fileName: fileName,
        studentName: _resolvedStudentName,
        reply: effectiveReply,
        onProgress: _updateMediaUploadProgress,
      );
      if (mounted) setState(() => selectedReply = null);
      shouldScrollAfterSending = true;
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'video',
          previewText: 'Video',
        ),
      );
      _clearMediaUploadState();
    } catch (error) {
      _failMediaUpload(
        _PendingAttachment(
          kind: _AttachmentKind.video,
          fileName: fileName,
          bytes: videoBytes,
          reply: effectiveReply,
        ),
      );
      _showUploadFailure(error, 'Failed to upload video');
    }
  }

  Future<void> _sendVoiceAttachment({
    required Uint8List voiceBytes,
    required String fileName,
    required int durationMs,
    MessageReply? reply,
    bool retrying = false,
  }) async {
    final effectiveReply = reply ?? selectedReply;
    _beginMediaUpload(
      retrying ? 'Retrying voice message...' : 'Uploading voice message...',
    );
    try {
      final messageId = await FirestoreChatService.sendVoiceMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        voiceBytes: voiceBytes,
        fileName: fileName,
        durationMs: durationMs,
        studentName: _resolvedStudentName,
        reply: effectiveReply,
        onProgress: _updateMediaUploadProgress,
      );
      if (mounted) setState(() => selectedReply = null);
      shouldScrollAfterSending = true;
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'voice',
          previewText: 'Voice message',
        ),
      );
      _clearMediaUploadState();
    } catch (error) {
      _failMediaUpload(
        _PendingAttachment(
          kind: _AttachmentKind.voice,
          fileName: fileName,
          bytes: voiceBytes,
          durationMs: durationMs,
          reply: effectiveReply,
        ),
      );
      _showUploadFailure(error, 'Failed to send voice message');
    }
  }

  Future<void> _sendDocumentAttachment({
    required Uint8List documentBytes,
    required String fileName,
    MessageReply? reply,
    bool retrying = false,
    String? uploadLabel,
  }) async {
    final effectiveReply = reply ?? selectedReply;
    _beginMediaUpload(
      uploadLabel ??
          (retrying ? 'Retrying document...' : 'Uploading document...'),
    );
    try {
      final messageId = await FirestoreChatService.sendDocumentMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        documentBytes: documentBytes,
        fileName: fileName,
        studentName: _resolvedStudentName,
        reply: effectiveReply,
        onProgress: _updateMediaUploadProgress,
      );
      if (mounted) setState(() => selectedReply = null);
      shouldScrollAfterSending = true;
      unawaited(
        _sendPushNotification(
          messageId: messageId,
          messageType: 'document',
          previewText: fileName,
        ),
      );
      _clearMediaUploadState();
    } catch (error) {
      _failMediaUpload(
        _PendingAttachment(
          kind: _AttachmentKind.document,
          fileName: fileName,
          bytes: documentBytes,
          reply: effectiveReply,
        ),
      );
      _showUploadFailure(error, 'Failed to upload document');
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> sortMessages(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final sortedDocs = [...docs];

    sortedDocs.sort((a, b) {
      final aCreatedAt = a.data()['created_at'];
      final bCreatedAt = b.data()['created_at'];

      if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
        return aCreatedAt.compareTo(bCreatedAt);
      }

      if (aCreatedAt == null && bCreatedAt != null) return 1;
      if (aCreatedAt != null && bCreatedAt == null) return -1;

      return 0;
    });

    return sortedDocs;
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = isSending || isUploadingMedia || isRecordingVoice;
    final isSendingOrUploading = isSending || isUploadingMedia;
    final chatSubtitle = isAnnouncementThread
        ? widget.currentUserRole == 'student'
              ? 'Course ${widget.courseId} - announcements only'
              : 'Course ${widget.courseId} - announcement chat'
        : 'Course ${widget.courseId}';
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        toolbarHeight: compact ? 70 : 76,
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              alignment: Alignment.center,
              child: Text(
                _chatAvatarLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chatSubtitle,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        _ChatStatusPill(
                          label: canSendInThread ? 'Live chat' : 'Read only',
                          icon: canSendInThread
                              ? Icons.bolt_rounded
                              : Icons.visibility_rounded,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isSearchingMessages ? 'Close search' : 'Search messages',
            onPressed: toggleMessageSearch,
            icon: Icon(
              isSearchingMessages ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.chatBackground,
              AppColors.sky.withValues(alpha: 0.48),
              AppColors.chatBackground,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              if (isSearchingMessages)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: TextField(
                    controller: searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search messages and files',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: messageSearchQuery.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                searchController.clear();
                                setState(() => messageSearchQuery = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (value) => setState(() {
                      messageSearchQuery = value.trim();
                    }),
                  ),
                ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirestoreChatService.getThread(
                    courseId: widget.courseId,
                    threadId: widget.threadId,
                  ),
                  builder: (context, threadSnapshot) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirestoreChatService.getMessages(
                        courseId: widget.courseId,
                        threadId: widget.threadId,
                        limit: messageLimit,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _ChatStateCard(
                            icon: Icons.error_outline_rounded,
                            title: 'Could not load this chat',
                            subtitle: '${snapshot.error}',
                            color: AppColors.danger,
                          );
                        }

                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const _ChatLoadingCard();
                        }

                        final threadData = threadSnapshot.data?.data();
                        scheduleAnnouncementRead(threadData);
                        final typingLabel = _typingLabel(threadData);
                        final docs = sortMessages(snapshot.data?.docs ?? []);
                        final allVisibleDocs = docs.reversed.toList();
                        final query = messageSearchQuery.toLowerCase();
                        final visibleDocs = query.isEmpty
                            ? allVisibleDocs
                            : allVisibleDocs.where((message) {
                                final data = message.data();
                                return _messagePreview(
                                      data,
                                    ).toLowerCase().contains(query) ||
                                    (data['file_name']
                                                ?.toString()
                                                .toLowerCase() ??
                                            '')
                                        .contains(query) ||
                                    (data['sender_name']
                                                ?.toString()
                                                .toLowerCase() ??
                                            '')
                                        .contains(query);
                              }).toList();
                        final canLoadOlder = docs.length >= messageLimit;
                        final currentLatestMessageId = docs.isEmpty
                            ? null
                            : docs.last.id;
                        final pinnedMessages = allVisibleDocs
                            .where(
                              (message) => message.data()['pinned'] == true,
                            )
                            .toList();
                        final pinnedMessage = pinnedMessages.isEmpty
                            ? null
                            : pinnedMessages.last;

                        restorePositionAfterLoadingOlderMessages();

                        if (currentLatestMessageId != latestMessageId) {
                          latestMessageId = currentLatestMessageId;
                          final latestSenderRole = docs.isEmpty
                              ? null
                              : docs.last.data()['sender_role']?.toString();
                          if (latestSenderRole != null &&
                              latestSenderRole != widget.currentUserRole) {
                            unawaited(markThreadAsRead());
                          }
                          if (hasScrolledToInitialBottom &&
                              !isLoadingOlderMessages) {
                            scrollToBottom();
                          }
                        }

                        if (!hasScrolledToInitialBottom && docs.isNotEmpty) {
                          hasScrolledToInitialBottom = true;
                          unawaited(scheduleInitialBottomScroll());
                        }

                        if (shouldScrollAfterSending && docs.isNotEmpty) {
                          shouldScrollAfterSending = false;
                          scrollToBottom();
                        }

                        final hasPendingUpload =
                            isUploadingMedia || failedAttachment != null;

                        if (docs.isEmpty && !hasPendingUpload) {
                          return _ChatStateCard(
                            icon: isAnnouncementThread
                                ? Icons.campaign_rounded
                                : Icons.forum_outlined,
                            title: isAnnouncementThread
                                ? 'No announcements yet'
                                : 'Start the conversation',
                            subtitle: isAnnouncementThread
                                ? widget.currentUserRole == 'student'
                                      ? 'Your teacher will post course updates here.'
                                      : 'Post the first course announcement here.'
                                : 'Send the first message when you are ready.',
                            color: AppColors.primary,
                          );
                        }

                        final showLoadOlder =
                            canLoadOlder && messageSearchQuery.isEmpty;
                        final pendingUploadCount = hasPendingUpload ? 1 : 0;

                        return Column(
                          children: [
                            if (pinnedMessage != null)
                              _PinnedMessageBanner(
                                preview: _messagePreview(pinnedMessage.data()),
                                onTap: () =>
                                    _jumpToBottomIfPossible(animate: true),
                              ),
                            if (isAnnouncementThread &&
                                widget.currentUserRole != 'student')
                              _AnnouncementReadReceiptsBar(
                                reads: _announcementReads(threadData),
                              ),
                            if (typingLabel != null)
                              _TypingIndicatorBar(label: typingLabel),
                            Expanded(
                              child: Stack(
                                children: [
                                  AnimatedSlide(
                                    offset: isInitialChatReady
                                        ? Offset.zero
                                        : const Offset(0, 0.015),
                                    duration: const Duration(milliseconds: 240),
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      opacity: isInitialChatReady ? 1 : 0,
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeOut,
                                      child: visibleDocs.isEmpty
                                          ? const _ChatStateCard(
                                              icon: Icons.search_off_rounded,
                                              title: 'No matching messages',
                                              subtitle:
                                                  'Try another word, sender name, or file name.',
                                              color: AppColors.muted,
                                            )
                                          : ListView.builder(
                                              controller: scrollController,
                                              reverse: true,
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    12,
                                                    12,
                                                    12,
                                                    8,
                                                  ),
                                              itemCount:
                                                  visibleDocs.length +
                                                  pendingUploadCount +
                                                  (showLoadOlder ? 1 : 0),
                                              itemBuilder: (context, index) {
                                                if (hasPendingUpload &&
                                                    index == 0) {
                                                  return _AttachmentStatusBar(
                                                    label:
                                                        mediaUploadLabel ??
                                                        (failedAttachment !=
                                                                null
                                                            ? _attachmentLabel(
                                                                failedAttachment!
                                                                    .kind,
                                                              )
                                                            : 'Uploading media'),
                                                    progress:
                                                        mediaUploadProgress,
                                                    onRetry:
                                                        failedAttachment == null
                                                        ? null
                                                        : retryLastAttachment,
                                                    canRetry:
                                                        failedAttachment !=
                                                        null,
                                                  );
                                                }

                                                final messageIndex =
                                                    index - pendingUploadCount;
                                                if (showLoadOlder &&
                                                    messageIndex ==
                                                        visibleDocs.length) {
                                                  return Center(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 8,
                                                          ),
                                                      child: TextButton.icon(
                                                        onPressed:
                                                            isLoadingOlderMessages
                                                            ? null
                                                            : loadOlderMessages,
                                                        icon:
                                                            isLoadingOlderMessages
                                                            ? const SizedBox(
                                                                width: 16,
                                                                height: 16,
                                                                child:
                                                                    CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2,
                                                                    ),
                                                              )
                                                            : const Icon(
                                                                Icons.history,
                                                              ),
                                                        label: const Text(
                                                          'Load older messages',
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }

                                                final message =
                                                    visibleDocs[messageIndex];
                                                final data = message.data();
                                                final canManageMessage =
                                                    _canManageMessage(
                                                      senderRole:
                                                          data['sender_role']
                                                              ?.toString() ??
                                                          '',
                                                      senderName:
                                                          data['sender_name']
                                                              ?.toString() ??
                                                          '',
                                                    );

                                                final showDateSeparator =
                                                    _shouldShowDateSeparator(
                                                      messageIndex,
                                                      visibleDocs,
                                                    );

                                                return Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    MessageBubble(
                                                      type:
                                                          data['type'] ??
                                                          'text',
                                                      text: data['text'] ?? '',
                                                      mediaUrl:
                                                          data['media_url'],
                                                      fileName:
                                                          data['file_name']
                                                              ?.toString(),
                                                      fileSizeBytes:
                                                          (data['file_size_bytes']
                                                                  as num?)
                                                              ?.toInt(),
                                                      fileType:
                                                          data['file_type']
                                                              ?.toString(),
                                                      durationMs:
                                                          data['duration_ms'],
                                                      attachments:
                                                          data['attachments']
                                                              is List
                                                          ? List<
                                                              Map<
                                                                String,
                                                                dynamic
                                                              >
                                                            >.from(
                                                              (data['attachments']
                                                                      as List)
                                                                  .whereType<
                                                                    Map
                                                                  >()
                                                                  .map(
                                                                    (item) =>
                                                                        Map<
                                                                          String,
                                                                          dynamic
                                                                        >.from(
                                                                          item,
                                                                        ),
                                                                  ),
                                                            )
                                                          : null,
                                                      senderName:
                                                          data['sender_name'] ??
                                                          '',
                                                      senderRole:
                                                          data['sender_role'] ??
                                                          '',
                                                      currentUserRole: widget
                                                          .currentUserRole,
                                                      currentSenderName:
                                                          widget.senderName,
                                                      createdAt:
                                                          data['created_at'],
                                                      editedAt:
                                                          data['edited_at'],
                                                      deletedAt:
                                                          data['deleted_at'],
                                                      replySenderName:
                                                          data['reply_to_sender_name']
                                                              ?.toString(),
                                                      replySenderRole:
                                                          data['reply_to_sender_role']
                                                              ?.toString(),
                                                      replyPreview:
                                                          data['reply_to_preview']
                                                              ?.toString(),
                                                      replyType:
                                                          data['reply_to_type']
                                                              ?.toString(),
                                                      forwarded:
                                                          data['forwarded'] ==
                                                          true,
                                                      pinned:
                                                          data['pinned'] ==
                                                          true,
                                                      reactions:
                                                          data['reactions']
                                                              is Map
                                                          ? Map<
                                                              String,
                                                              dynamic
                                                            >.from(
                                                              data['reactions']
                                                                  as Map,
                                                            )
                                                          : null,
                                                      deliveryStatus:
                                                          _messageDeliveryStatus(
                                                            data: data,
                                                            threadData:
                                                                threadData,
                                                            hasPendingWrites:
                                                                message
                                                                    .metadata
                                                                    .hasPendingWrites,
                                                          ),
                                                      onReply: canSendInThread
                                                          ? () =>
                                                                replyToMessage(
                                                                  messageId:
                                                                      message
                                                                          .id,
                                                                  data: data,
                                                                )
                                                          : null,
                                                      onReact:
                                                          data['deleted_at'] ==
                                                              null
                                                          ? () =>
                                                                reactToMessage(
                                                                  message.id,
                                                                )
                                                          : null,
                                                      onForward:
                                                          canForwardMessages &&
                                                              data['deleted_at'] ==
                                                                  null
                                                          ? () =>
                                                                forwardMessage(
                                                                  data: data,
                                                                )
                                                          : null,
                                                      onTogglePin:
                                                          canPinMessages &&
                                                              data['deleted_at'] ==
                                                                  null
                                                          ? () => togglePinMessage(
                                                              messageId:
                                                                  message.id,
                                                              currentlyPinned:
                                                                  data['pinned'] ==
                                                                  true,
                                                              data: data,
                                                            )
                                                          : null,
                                                      onEdit:
                                                          canManageMessage &&
                                                              data['type'] ==
                                                                  'text' &&
                                                              data['deleted_at'] ==
                                                                  null
                                                          ? () => editMessage(
                                                              messageId:
                                                                  message.id,
                                                              currentText:
                                                                  data['text']
                                                                      ?.toString() ??
                                                                  '',
                                                            )
                                                          : null,
                                                      onDelete:
                                                          canManageMessage &&
                                                              data['deleted_at'] ==
                                                                  null
                                                          ? () => deleteMessage(
                                                              messageId:
                                                                  message.id,
                                                              data: data,
                                                            )
                                                          : null,
                                                    ),
                                                    if (showDateSeparator)
                                                      _DateSeparator(
                                                        label: _messageDateLabel(
                                                          data['created_at'],
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              },
                                            ),
                                    ),
                                  ),
                                  if (!isInitialChatReady)
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                        child: Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
              if (widget.currentUserRole != 'admin' && !isAnnouncementThread)
                _ReadReceiptBar(
                  currentUserRole: widget.currentUserRole,
                  threadStream: FirestoreChatService.getThread(
                    courseId: widget.courseId,
                    threadId: widget.threadId,
                  ),
                ),
              SafeArea(
                child: canSendInThread
                    ? Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: const Border(
                            top: BorderSide(color: AppColors.border),
                          ),
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
                            if (selectedReply != null && !isRecordingVoice) ...[
                              _ReplyComposerPreview(
                                reply: selectedReply!,
                                onCancel: cancelReply,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (isAnnouncementThread && !isRecordingVoice) ...[
                              _AnnouncementTemplateRow(
                                onUseTemplate: (template) {
                                  messageController.text = template;
                                  messageController.selection =
                                      TextSelection.collapsed(
                                        offset: messageController.text.length,
                                      );
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: isRecordingVoice
                                      ? cancelVoiceRecording
                                      : isBusy
                                      ? null
                                      : showAttachmentOptions,
                                  style: IconButton.styleFrom(
                                    foregroundColor: isRecordingVoice
                                        ? AppColors.danger
                                        : null,
                                  ),
                                  icon: Icon(
                                    isRecordingVoice
                                        ? Icons.delete_outline_rounded
                                        : Icons.add,
                                  ),
                                  tooltip: isRecordingVoice
                                      ? 'Cancel recording'
                                      : 'Add attachment',
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: isRecordingVoice
                                      ? _RecordingComposerPill(
                                          duration: _formatRecordingDuration(),
                                          isPaused: isVoiceRecordingPaused,
                                          onTogglePause:
                                              toggleVoiceRecordingPause,
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            border: Border.all(
                                              color: AppColors.border,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primaryDark
                                                    .withValues(alpha: 0.04),
                                                blurRadius: 14,
                                                offset: const Offset(0, 6),
                                              ),
                                            ],
                                          ),
                                          child: TextField(
                                            controller: messageController,
                                            enabled: !isBusy,
                                            maxLines: 5,
                                            minLines: 1,
                                            textCapitalization:
                                                TextCapitalization.sentences,
                                            decoration: InputDecoration(
                                              hintText: isUploadingMedia
                                                  ? 'Uploading media...'
                                                  : 'Write a message',
                                              filled: false,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14,
                                                  ),
                                              border: InputBorder.none,
                                            ),
                                            onSubmitted: (_) => sendMessage(),
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                if (!isRecordingVoice) ...[
                                  IconButton.filledTonal(
                                    onPressed: isSendingOrUploading
                                        ? null
                                        : toggleVoiceRecording,
                                    style: IconButton.styleFrom(
                                      foregroundColor: AppColors.primary,
                                    ),
                                    icon: const Icon(Icons.mic_none),
                                    tooltip: 'Record voice message',
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                FilledButton(
                                  onPressed: isSendingOrUploading
                                      ? null
                                      : isRecordingVoice
                                      ? stopAndSendVoiceMessage
                                      : sendMessage,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.square(48),
                                    padding: EdgeInsets.zero,
                                    shape: const CircleBorder(),
                                  ),
                                  child: isSendingOrUploading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : _ReadOnlyChatBar(
                        message: widget.readOnly
                            ? 'Manager operation access is view-only for this chat.'
                            : 'Announcements are read-only. Reply in your teacher chat.',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowDateSeparator(
    int messageIndex,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> messages,
  ) {
    final current = messages[messageIndex].data()['created_at'];
    if (messageIndex == messages.length - 1) return true;

    final next = messages[messageIndex + 1].data()['created_at'];
    return _messageDayKey(current) != _messageDayKey(next);
  }

  String _messageDayKey(dynamic timestamp) {
    final date = _messageDate(timestamp);
    if (date == null) return 'pending';
    return '${date.year}-${date.month}-${date.day}';
  }

  String _messageDateLabel(dynamic timestamp) {
    final date = _messageDate(timestamp);
    if (date == null) return 'Sending';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(date.year, date.month, date.day);
    final difference = today.difference(messageDay).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  DateTime? _messageDate(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is Timestamp) return timestamp.toDate();
    if (timestamp is DateTime) return timestamp;
    return null;
  }

  String _formatRecordingDuration() {
    final minutes = recordingDuration.inMinutes;
    final seconds = recordingDuration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get _chatAvatarLabel {
    final trimmedTitle = widget.title.trim();
    if (trimmedTitle.isEmpty) return '?';

    final words = trimmedTitle.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return trimmedTitle.substring(0, 1).toUpperCase();
    }

    final first = words.first.isEmpty ? '?' : words.first.substring(0, 1);
    final second = words[1].isEmpty ? '?' : words[1].substring(0, 1);
    return (first + second).toUpperCase();
  }

  String? get _resolvedStudentName {
    final explicitName = widget.threadStudentName?.trim();
    if (explicitName != null && explicitName.isNotEmpty) {
      return explicitName;
    }

    if (widget.currentUserRole == 'student') {
      return widget.senderName;
    }

    return null;
  }

  bool _canManageMessage({
    required String senderRole,
    required String senderName,
  }) {
    if (widget.readOnly) return false;
    if (widget.isSuperAdmin || widget.canManageAllMessages) return true;

    return senderRole == widget.currentUserRole &&
        senderName == widget.senderName;
  }

  MessageDeliveryStatus? _messageDeliveryStatus({
    required Map<String, dynamic> data,
    required Map<String, dynamic>? threadData,
    required bool hasPendingWrites,
  }) {
    final senderRole = data['sender_role']?.toString();
    final senderName = data['sender_name']?.toString();
    final isOwnMessage =
        senderRole == widget.currentUserRole && senderName == widget.senderName;

    if (!isOwnMessage || data['deleted_at'] != null) return null;
    if (hasPendingWrites) return MessageDeliveryStatus.sending;

    final createdAt = data['created_at'];
    if (createdAt is! Timestamp) return MessageDeliveryStatus.sending;

    if (isAnnouncementThread ||
        (widget.currentUserRole == 'admin' &&
            !isAdminTeacherThread &&
            !isKeyPersonStudentThread)) {
      return MessageDeliveryStatus.sent;
    }

    final otherReadAt = threadData == null
        ? null
        : isAdminTeacherThread
        ? widget.currentUserRole == 'admin'
              ? threadData['teacher_last_read_at']
              : threadData['admin_last_read_at']
        : isKeyPersonStudentThread
        ? widget.currentUserRole == 'admin'
              ? threadData['student_last_read_at']
              : threadData['admin_last_read_at']
        : widget.currentUserRole == 'student'
        ? threadData['teacher_last_read_at']
        : threadData['student_last_read_at'];

    if (otherReadAt is Timestamp && otherReadAt.compareTo(createdAt) >= 0) {
      return MessageDeliveryStatus.seen;
    }

    return MessageDeliveryStatus.delivered;
  }

  String? _typingLabel(Map<String, dynamic>? threadData) {
    if (threadData == null || threadData['typing_active'] != true) {
      return null;
    }

    final typingRole = threadData['typing_role']?.toString() ?? '';
    final typingName = threadData['typing_name']?.toString() ?? '';
    final typingAt = threadData['typing_at'];
    final typedAt = typingAt is Timestamp ? typingAt.toDate() : null;

    if (typedAt == null ||
        DateTime.now().difference(typedAt) > const Duration(seconds: 8)) {
      return null;
    }

    if (typingRole == widget.currentUserRole &&
        typingName == widget.senderName) {
      return null;
    }

    final roleLabel = switch (typingRole) {
      'teacher' => 'Teacher',
      'student' => 'Student',
      'admin' => 'EACC Admin',
      _ => 'Someone',
    };

    return typingName.isEmpty
        ? '$roleLabel is typing...'
        : '$typingName is typing...';
  }

  List<_AnnouncementRead> _announcementReads(Map<String, dynamic>? threadData) {
    final reads = threadData?['announcement_reads'];
    if (reads is! Map) return const [];

    final entriesByReader = <String, _AnnouncementRead>{};
    for (final entry in reads.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      String role;
      String displayName;
      DateTime? readAt;

      if (value is Map) {
        role = value['role']?.toString().trim().toLowerCase() ?? '';
        displayName = value['display_name']?.toString().trim() ?? '';
        final rawTime = value['read_at'];
        readAt = rawTime is Timestamp ? rawTime.toDate() : null;
      } else {
        final parts = key.split('_');
        role = parts.isNotEmpty ? parts.first.toLowerCase() : '';
        displayName = parts.length > 1
            ? parts.skip(1).join(' ').trim()
            : key.replaceAll('_', ' ').trim();
        readAt = value is Timestamp ? value.toDate() : null;
      }

      if (role != 'student' || displayName.isEmpty) continue;

      final reader = _AnnouncementRead(
        role: role,
        displayName: displayName,
        readAt: readAt,
      );
      final identity = displayName.toLowerCase();
      final existing = entriesByReader[identity];
      if (existing == null ||
          (reader.readAt != null &&
              (existing.readAt == null ||
                  reader.readAt!.isAfter(existing.readAt!)))) {
        entriesByReader[identity] = reader;
      }
    }

    final entries = entriesByReader.values.toList();

    entries.sort((a, b) {
      final aTime = a.readAt;
      final bTime = b.readAt;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return entries;
  }

  String _messagePreview(Map<String, dynamic> data) {
    if (data['deleted_at'] != null) return 'Deleted message';

    final type = data['type']?.toString() ?? 'text';
    final text = data['text']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;

    switch (type) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'media_group':
        final count = data['media_count'] as int? ?? 0;
        return count > 0 ? ' media files' : 'Media';
      case 'voice':
        return 'Voice message';
      case 'document':
        final fileName = data['file_name']?.toString().trim() ?? '';
        return fileName.isNotEmpty ? fileName : 'Document';
      default:
        return 'Message';
    }
  }

  Future<void> _sendPushNotification({
    required String messageId,
    required String messageType,
    required String previewText,
  }) async {
    if (widget.isSuperAdmin) return;

    // Student, teacher, and scoped key-person admins send push notifications.

    try {
      debugPrint(
        'Sending push notification: course=${widget.courseId}, '
        'thread=${widget.threadId}, type=$messageType',
      );
      await _notificationApi.notifyChatMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderRole: widget.currentUserRole,
        senderName: widget.senderName,
        messageType: messageType,
        messageId: messageId,
        previewText: previewText,
        studentName: _resolvedStudentName,
        audience: _notificationAudience,
      );
    } catch (error) {
      debugPrint('Push notification send failed: $error');
    }
  }

  String? get _notificationAudience {
    if (isAnnouncementThread) return 'course';
    if (isKeyPersonStudentThread) {
      if (widget.currentUserRole == 'admin') return 'keyperson_student';
      if (widget.currentUserRole == 'student') return 'keyperson';
      return null;
    }
    if (!isAdminTeacherThread) return null;

    if (widget.currentUserRole == 'admin') return 'teachers';
    if (widget.currentUserRole == 'teacher') return 'admins';
    return null;
  }

  void _beginMediaUpload(String label) {
    if (!mounted) return;
    setState(() {
      isUploadingMedia = true;
      mediaUploadProgress = 0;
      mediaUploadLabel = label;
      failedAttachment = null;
    });
  }

  void _updateMediaUploadProgress(double progress) {
    if (!mounted) return;
    setState(() {
      mediaUploadProgress = progress.clamp(0.0, 1.0);
    });
  }

  void _clearMediaUploadState() {
    if (!mounted) return;
    setState(() {
      isUploadingMedia = false;
      mediaUploadProgress = null;
      mediaUploadLabel = null;
      failedAttachment = null;
    });
  }

  void _failMediaUpload(_PendingAttachment attachment) {
    if (!mounted) return;
    setState(() {
      isUploadingMedia = false;
      mediaUploadProgress = null;
      mediaUploadLabel = null;
      failedAttachment = attachment;
    });
  }

  void _showUploadFailure(Object error, String fallbackMessage) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$fallbackMessage: $error'),
        action: failedAttachment == null
            ? null
            : SnackBarAction(label: 'Retry', onPressed: retryLastAttachment),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  String _attachmentLabel(_AttachmentKind kind) {
    switch (kind) {
      case _AttachmentKind.image:
        return 'Photo upload';
      case _AttachmentKind.video:
        return 'Video upload';
      case _AttachmentKind.voice:
        return 'Voice message upload';
      case _AttachmentKind.document:
        return 'Document upload';
    }
  }

  Future<void> _logFirestoreSendDebug(Object error) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final token = await user?.getIdTokenResult(true);
      debugPrint(
        'Firestore send failed: $error\n'
        'chatRole=${widget.currentUserRole}, courseId=${widget.courseId}, '
        'threadId=${widget.threadId}, senderName=${widget.senderName}, '
        'studentName=$_resolvedStudentName\n'
        'firebaseUid=${user?.uid}, firebaseRole=${token?.claims?['role']}, '
        'firebaseIsSuperAdmin=${token?.claims?['isSuperAdmin']}, '
        'firebaseCanViewAllCourses=${token?.claims?['canViewAllCourses']}, '
        'firebaseLmsUserId=${token?.claims?['lmsUserId']}, '
        'firebaseDisplayName=${token?.claims?['displayName']}, '
        'firebaseCourseIds=${token?.claims?['courseIds']}',
      );
    } catch (debugError) {
      debugPrint('Could not read Firebase debug claims: $debugError');
    }
  }

  Uint8List _createWavFile(
    Uint8List pcmBytes, {
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final header = ByteData(44);
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;

    void writeText(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeText(0, 'RIFF');
    header.setUint32(4, 36 + pcmBytes.length, Endian.little);
    writeText(8, 'WAVE');
    writeText(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeText(36, 'data');
    header.setUint32(40, pcmBytes.length, Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcmBytes]);
  }

  bool _containsAudibleAudio(Uint8List wavBytes) {
    if (wavBytes.length <= 44) return false;

    final samples = ByteData.sublistView(wavBytes, 44);
    var peak = 0;
    for (var offset = 0; offset + 1 < samples.lengthInBytes; offset += 2) {
      final amplitude = samples.getInt16(offset, Endian.little).abs();
      if (amplitude > peak) peak = amplitude;
      if (peak >= 160) return true;
    }

    return false;
  }
}

class _AnnouncementRead {
  final String role;
  final String displayName;
  final DateTime? readAt;

  const _AnnouncementRead({
    required this.role,
    required this.displayName,
    required this.readAt,
  });
}

class _TypingIndicatorBar extends StatelessWidget {
  final String label;

  const _TypingIndicatorBar({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementReadReceiptsBar extends StatelessWidget {
  final List<_AnnouncementRead> reads;

  const _AnnouncementReadReceiptsBar({required this.reads});

  @override
  Widget build(BuildContext context) {
    final count = reads.length;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.fact_check_rounded,
                  color: AppColors.success,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0
                          ? 'No student reads yet'
                          : count == 1
                          ? 'Read by 1 student'
                          : 'Read by $count students',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'For the latest announcement',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Announcement read receipts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  reads.isEmpty
                      ? 'No students have opened the latest announcement yet.'
                      : '${reads.length} student${reads.length == 1 ? '' : 's'} read the latest announcement',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 14),
                if (reads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Readers will appear here as students open the announcement chat.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: reads.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final read = reads[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            child: Text(
                              read.displayName.trim().isEmpty
                                  ? '?'
                                  : read.displayName.trim()[0].toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: Text(
                            read.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(_roleLabel(read.role)),
                          trailing: Text(
                            read.readAt == null
                                ? ''
                                : formatThreadTime(read.readAt!),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'student' => 'Student',
      'teacher' => 'Teacher',
      'admin' => 'Admin',
      _ => 'Reader',
    };
  }
}

class _ReadReceiptBar extends StatelessWidget {
  final String currentUserRole;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> threadStream;

  const _ReadReceiptBar({
    required this.currentUserRole,
    required this.threadStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: threadStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final status = _readReceiptStatus(data);

        if (status == null) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          alignment: Alignment.centerRight,
          child: Text(
            status,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }

  String? _readReceiptStatus(Map<String, dynamic>? data) {
    if (data == null) return null;
    if (data['last_sender_role'] != currentUserRole) return null;

    final lastMessageAt = data['last_message_at'];
    final otherReadAt = currentUserRole == 'student'
        ? data['teacher_last_read_at']
        : data['student_last_read_at'];

    if (lastMessageAt is! Timestamp) return null;
    if (otherReadAt is Timestamp && otherReadAt.compareTo(lastMessageAt) >= 0) {
      return 'Seen';
    }

    return 'Delivered';
  }
}

class _PinnedMessageBanner extends StatelessWidget {
  final String preview;
  final VoidCallback onTap;

  const _PinnedMessageBanner({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.push_pin_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Pinned message',
                      style: TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForwardDestination {
  final String threadId;
  final String title;
  final String? studentName;

  const _ForwardDestination({
    required this.threadId,
    required this.title,
    this.studentName,
  });
}

class _ReplyComposerPreview extends StatelessWidget {
  final MessageReply reply;
  final VoidCallback onCancel;

  const _ReplyComposerPreview({required this.reply, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final sender = reply.senderRole == 'admin'
        ? 'EACC Admin'
        : reply.senderName.trim().isEmpty
        ? 'Message'
        : reply.senderName.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to $sender',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reply.preview,
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
          IconButton(
            onPressed: onCancel,
            tooltip: 'Cancel reply',
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _RecordingComposerPill extends StatelessWidget {
  final String duration;
  final bool isPaused;
  final VoidCallback onTogglePause;

  const _RecordingComposerPill({
    required this.duration,
    required this.isPaused,
    required this.onTogglePause,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 19,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPaused ? 'Paused $duration' : 'Recording $duration',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isPaused ? AppColors.muted : AppColors.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPaused
                      ? 'Resume to continue, or send what you recorded'
                      : 'Tap pause or send when you are done',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            onPressed: onTogglePause,
            icon: Icon(
              isPaused ? Icons.mic_rounded : Icons.pause_rounded,
              size: 19,
            ),
            tooltip: isPaused ? 'Resume recording' : 'Pause recording',
            style: IconButton.styleFrom(
              foregroundColor: isPaused ? AppColors.primary : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyChatBar extends StatelessWidget {
  final String message;

  const _ReadOnlyChatBar({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.1),
            AppColors.sky.withValues(alpha: 0.68),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(
              Icons.visibility_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatStatusPill extends StatelessWidget {
  final String label;
  final IconData icon;

  const _ChatStatusPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatLoadingCard extends StatelessWidget {
  const _ChatLoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _ChatStateCard(
      icon: Icons.forum_rounded,
      title: 'Loading chat',
      subtitle: 'Preparing messages, files, and read status.',
      color: AppColors.primary,
    );
  }
}

class _ChatStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _ChatStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, size: 34, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  final String label;

  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementTemplateRow extends StatelessWidget {
  final ValueChanged<String> onUseTemplate;

  const _AnnouncementTemplateRow({required this.onUseTemplate});

  static const templates = [
    'Reminder: please check today\'s lesson update.',
    'Homework has been added. Please review it before next class.',
    'Schedule update: your teacher will confirm the next session time.',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: templates
            .map(
              (template) => ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text(
                  template.length > 34
                      ? '${template.substring(0, 34)}...'
                      : template,
                ),
                onPressed: () => onUseTemplate(template),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AttachmentStatusBar extends StatelessWidget {
  final String label;
  final double? progress;
  final VoidCallback? onRetry;
  final bool canRetry;

  const _AttachmentStatusBar({
    required this.label,
    required this.progress,
    required this.onRetry,
    required this.canRetry,
  });

  @override
  Widget build(BuildContext context) {
    final progressValue = progress?.clamp(0.0, 1.0);

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.fromLTRB(48, 6, 0, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            border: Border.all(color: const Color(0xFFC8DCF7)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      value: progressValue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (canRetry && onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 4,
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                canRetry ? 'Upload failed' : 'Sending attachment...',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AttachmentKind { image, video, voice, document }

class _PendingAttachment {
  final _AttachmentKind kind;
  final String fileName;
  final Uint8List bytes;
  final int? durationMs;
  final MessageReply? reply;

  const _PendingAttachment({
    required this.kind,
    required this.fileName,
    required this.bytes,
    this.durationMs,
    this.reply,
  });
}
