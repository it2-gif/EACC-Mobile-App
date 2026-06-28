import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../services/firestore_chat_service.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String title;
  final String currentUserRole;
  final String courseId;
  final String threadId;
  final String senderName;
  final String? threadStudentName;

  const ChatScreen({
    super.key,
    required this.title,
    required this.currentUserRole,
    required this.courseId,
    required this.threadId,
    required this.senderName,
    this.threadStudentName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int messagesPerPage = 30;
  static final NotificationApi _notificationApi = NotificationApi();

  final messageController = TextEditingController();
  final scrollController = ScrollController();
  final audioRecorder = AudioRecorder();
  final voiceChunks = <Uint8List>[];

  bool isSending = false;
  bool isUploadingMedia = false;
  bool isRecordingVoice = false;
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

  bool get isAnnouncementThread =>
      widget.threadId == FirestoreChatService.announcementThreadId;

  bool get canSendInThread =>
      !isAnnouncementThread || widget.currentUserRole != 'student';

  @override
  void dispose() {
    recordingTimer?.cancel();
    recordingSubscription?.cancel();
    audioRecorder.dispose();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(markThreadAsRead());
    });
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
    if (widget.currentUserRole == 'admin' || isAnnouncementThread) return;

    try {
      await FirestoreChatService.markThreadRead(
        courseId: widget.courseId,
        threadId: widget.threadId,
        readerRole: widget.currentUserRole,
        studentName: _resolvedStudentName,
      );
    } catch (_) {}
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
                    child: const Icon(Icons.image, color: AppColors.primary),
                  ),
                  title: const Text('Image'),
                  subtitle: const Text('Choose an existing photo'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendImage(ImageSource.gallery);
                  },
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
                    child: const Icon(
                      Icons.video_library,
                      color: AppColors.primary,
                    ),
                  ),
                  title: const Text('Video'),
                  subtitle: const Text('Choose an existing video'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendVideo(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: const Icon(Icons.videocam, color: AppColors.primary),
                  ),
                  title: const Text('Record video'),
                  subtitle: const Text('Capture and send immediately'),
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendVideo(ImageSource.camera);
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
        });
      }
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

    setState(() {
      isSending = true;
      shouldScrollAfterSending = true;
    });

    try {
      final messageId = await FirestoreChatService.sendTextMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        text: text,
        studentName: _resolvedStudentName,
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to edit message: $error')),
        );
      }
    }
  }

  Future<void> deleteMessage(String messageId) async {
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete message: $error')),
        );
      }
    }
  }

  Future<void> pickAndSendImage(ImageSource source) async {
    if (isUploadingMedia || isSending || isRecordingVoice) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 85);

    if (image == null) return;

    setState(() => isUploadingMedia = true);

    try {
      final imageSize = await image.length();
      FirestoreChatService.validateImageUpload(
        fileName: image.name,
        fileSize: imageSize,
      );

      final imageBytes = await image.readAsBytes();
      shouldScrollAfterSending = true;

      await _sendImageAttachment(imageBytes: imageBytes, fileName: image.name);
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
    }

    if (mounted) setState(() => isUploadingMedia = false);
  }

  Future<void> pickAndSendVideo(ImageSource source) async {
    if (isUploadingMedia || isSending || isRecordingVoice) return;

    final video = await ImagePicker().pickVideo(
      source: source,
      maxDuration: const Duration(minutes: 2),
    );
    if (video == null) return;

    setState(() => isUploadingMedia = true);

    try {
      final videoSize = await video.length();
      FirestoreChatService.validateVideoUpload(
        fileName: video.name,
        fileSize: videoSize,
      );
      final videoBytes = await video.readAsBytes();
      shouldScrollAfterSending = true;

      await _sendVideoAttachment(videoBytes: videoBytes, fileName: video.name);
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

    if (mounted) setState(() => isUploadingMedia = false);
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
          retrying: true,
        );
        break;
      case _AttachmentKind.video:
        await _sendVideoAttachment(
          videoBytes: attachment.bytes,
          fileName: attachment.fileName,
          retrying: true,
        );
        break;
      case _AttachmentKind.voice:
        await _sendVoiceAttachment(
          voiceBytes: attachment.bytes,
          fileName: attachment.fileName,
          durationMs: attachment.durationMs ?? 0,
          retrying: true,
        );
        break;
    }
  }

  Future<void> _sendImageAttachment({
    required Uint8List imageBytes,
    required String fileName,
    bool retrying = false,
  }) async {
    _beginMediaUpload(retrying ? 'Retrying photo...' : 'Uploading photo...');
    try {
      final messageId = await FirestoreChatService.sendImageMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        imageBytes: imageBytes,
        fileName: fileName,
        studentName: _resolvedStudentName,
        onProgress: _updateMediaUploadProgress,
      );
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
        ),
      );
      _showUploadFailure(error, 'Failed to upload image');
    }
  }

  Future<void> _sendVideoAttachment({
    required Uint8List videoBytes,
    required String fileName,
    bool retrying = false,
  }) async {
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
        onProgress: _updateMediaUploadProgress,
      );
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
        ),
      );
      _showUploadFailure(error, 'Failed to upload video');
    }
  }

  Future<void> _sendVoiceAttachment({
    required Uint8List voiceBytes,
    required String fileName,
    required int durationMs,
    bool retrying = false,
  }) async {
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
        onProgress: _updateMediaUploadProgress,
      );
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
        ),
      );
      _showUploadFailure(error, 'Failed to send voice message');
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

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        toolbarHeight: 72,
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
                borderRadius: BorderRadius.circular(8),
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
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chatSubtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (isUploadingMedia)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: const Color(0xFFFFF3CD),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Uploading media...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF7A4E00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (isUploadingMedia || failedAttachment != null)
            _AttachmentStatusBar(
              label:
                  mediaUploadLabel ??
                  (failedAttachment != null
                      ? _attachmentLabel(failedAttachment!.kind)
                      : 'Uploading media'),
              progress: mediaUploadProgress,
              onRetry: failedAttachment == null ? null : retryLastAttachment,
              canRetry: failedAttachment != null,
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
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.red.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Something went wrong',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.admin,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final docs = sortMessages(snapshot.data?.docs ?? []);
                    final visibleDocs = docs.reversed.toList();
                    final canLoadOlder = docs.length >= messageLimit;
                    final currentLatestMessageId = docs.isEmpty
                        ? null
                        : docs.last.id;

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

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Icon(
                                  Icons.forum_outlined,
                                  size: 34,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                isAnnouncementThread
                                    ? 'No announcements yet'
                                    : 'No messages yet',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isAnnouncementThread
                                    ? widget.currentUserRole == 'student'
                                          ? 'Your teacher will post course updates here.'
                                          : 'Post the first course announcement here.'
                                    : 'Send the first message to start this conversation.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return Stack(
                      children: [
                        AnimatedSlide(
                          offset: isInitialChatReady
                              ? Offset.zero
                              : const Offset(0, 0.015),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: isInitialChatReady ? 1 : 0,
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            child: ListView.builder(
                              controller: scrollController,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                              itemCount: docs.length + (canLoadOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (canLoadOlder &&
                                    index == visibleDocs.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextButton.icon(
                                        onPressed: isLoadingOlderMessages
                                            ? null
                                            : loadOlderMessages,
                                        icon: isLoadingOlderMessages
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.history),
                                        label: const Text(
                                          'Load older messages',
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final message = visibleDocs[index];
                                final data = message.data();
                                final canManageMessage = _canManageMessage(
                                  senderRole:
                                      data['sender_role']?.toString() ?? '',
                                  senderName:
                                      data['sender_name']?.toString() ?? '',
                                );

                                return MessageBubble(
                                  type: data['type'] ?? 'text',
                                  text: data['text'] ?? '',
                                  mediaUrl: data['media_url'],
                                  durationMs: data['duration_ms'],
                                  senderName: data['sender_name'] ?? '',
                                  senderRole: data['sender_role'] ?? '',
                                  currentUserRole: widget.currentUserRole,
                                  currentSenderName: widget.senderName,
                                  createdAt: data['created_at'],
                                  editedAt: data['edited_at'],
                                  deletedAt: data['deleted_at'],
                                  onEdit:
                                      canManageMessage &&
                                          data['type'] == 'text' &&
                                          data['deleted_at'] == null
                                      ? () => editMessage(
                                          messageId: message.id,
                                          currentText:
                                              data['text']?.toString() ?? '',
                                        )
                                      : null,
                                  onDelete:
                                      canManageMessage &&
                                          data['deleted_at'] == null
                                      ? () => deleteMessage(message.id)
                                      : null,
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
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                    child: Row(
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
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.background,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppColors.border),
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
                  )
                : const _ReadOnlyAnnouncementBar(),
          ),
        ],
      ),
    );
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
    if (widget.currentUserRole == 'admin') return true;

    return senderRole == widget.currentUserRole &&
        senderName == widget.senderName;
  }

  Future<void> _sendPushNotification({
    required String messageId,
    required String messageType,
    required String previewText,
  }) async {
    // All roles (student, teacher, admin) send push notifications.

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
        audience: isAnnouncementThread ? 'course' : null,
      );
    } catch (error) {
      debugPrint('Push notification send failed: $error');
    }
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

class _RecordingComposerPill extends StatelessWidget {
  final String duration;

  const _RecordingComposerPill({required this.duration});

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
                  'Recording $duration',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap send when you are done',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

class _ReadOnlyAnnouncementBar extends StatelessWidget {
  const _ReadOnlyAnnouncementBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: const Row(
        children: [
          Icon(Icons.campaign_rounded, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Announcements are read-only. Reply in your teacher chat.',
              style: TextStyle(
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

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
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
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progressValue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
            child: LinearProgressIndicator(value: progressValue, minHeight: 4),
          ),
        ],
      ),
    );
  }
}

enum _AttachmentKind { image, video, voice }

class _PendingAttachment {
  final _AttachmentKind kind;
  final String fileName;
  final Uint8List bytes;
  final int? durationMs;

  const _PendingAttachment({
    required this.kind,
    required this.fileName,
    required this.bytes,
    this.durationMs,
  });
}
