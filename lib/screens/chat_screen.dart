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
  int messageLimit = messagesPerPage;
  String? latestMessageId;
  double scrollOffsetBeforeLoadingOlder = 0;
  double scrollExtentBeforeLoadingOlder = 0;
  Duration recordingDuration = Duration.zero;
  Timer? recordingTimer;
  StreamSubscription<Uint8List>? recordingSubscription;
  int recordingSampleRate = 16000;

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
      if (!mounted || !scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> markThreadAsRead() async {
    if (widget.currentUserRole == 'admin') return;

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
    if (isSending || isUploadingMedia) return;
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

      await FirestoreChatService.sendVoiceMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        voiceBytes: voiceBytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
        durationMs: recordingDuration.inMilliseconds,
        studentName: _resolvedStudentName,
      );
      unawaited(
        _sendPushNotification(
          messageType: 'voice',
          previewText: 'Voice message',
        ),
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

    if (text.isEmpty || isSending || isUploadingMedia || isRecordingVoice) {
      return;
    }

    messageController.clear();

    setState(() {
      isSending = true;
      shouldScrollAfterSending = true;
    });

    try {
      await FirestoreChatService.sendTextMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        text: text,
        studentName: _resolvedStudentName,
      );
      unawaited(
        _sendPushNotification(messageType: 'text', previewText: text),
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

      await FirestoreChatService.sendImageMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        imageBytes: imageBytes,
        fileName: image.name,
        studentName: _resolvedStudentName,
      );
      unawaited(
        _sendPushNotification(messageType: 'image', previewText: 'Photo'),
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

      await FirestoreChatService.sendVideoMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderName: widget.senderName,
        senderRole: widget.currentUserRole,
        videoBytes: videoBytes,
        fileName: video.name,
        studentName: _resolvedStudentName,
      );
      unawaited(
        _sendPushNotification(messageType: 'video', previewText: 'Video'),
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

    if (mounted) setState(() => isUploadingMedia = false);
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

    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              child: const Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Course ${widget.courseId}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
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
          if (isRecordingVoice)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppColors.danger.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(
                    Icons.fiber_manual_record,
                    size: 16,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recording ${_formatRecordingDuration()}',
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: cancelVoiceRecording,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Cancel'),
                  ),
                ],
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
                  if (!isLoadingOlderMessages) {
                    scrollToBottom();
                  }
                }

                if (shouldScrollAfterSending && docs.isNotEmpty) {
                  shouldScrollAfterSending = false;
                  scrollToBottom();
                }

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppColors.muted,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No messages yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Start the conversation',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: docs.length + (canLoadOlder ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (canLoadOlder && index == 0) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextButton.icon(
                            onPressed: isLoadingOlderMessages
                                ? null
                                : loadOlderMessages,
                            icon: isLoadingOlderMessages
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.history),
                            label: const Text('Load older messages'),
                          ),
                        ),
                      );
                    }

                    final messageIndex = canLoadOlder ? index - 1 : index;
                    final data = docs[messageIndex].data();

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
                    );
                  },
                );
                  },
                );
              },
            ),
          ),
          if (widget.currentUserRole != 'admin')
            _ReadReceiptBar(
              currentUserRole: widget.currentUserRole,
              threadStream: FirestoreChatService.getThread(
                courseId: widget.courseId,
                threadId: widget.threadId,
              ),
            ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(top: BorderSide(color: AppColors.border)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: isBusy ? null : showAttachmentOptions,
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primary,
                  ),
                  Expanded(
                    child: TextField(
                      controller: messageController,
                      enabled: !isBusy,
                      maxLines: 4,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: isRecordingVoice
                            ? 'Recording ${_formatRecordingDuration()}'
                            : isUploadingMedia
                            ? 'Uploading media...'
                            : 'Type a message',
                        filled: true,
                        fillColor: AppColors.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: isSending || isUploadingMedia
                        ? null
                        : toggleVoiceRecording,
                    icon: Icon(isRecordingVoice ? Icons.stop : Icons.mic_none),
                    color: isRecordingVoice
                        ? AppColors.danger
                        : AppColors.primary,
                    tooltip: isRecordingVoice
                        ? 'Stop and send'
                        : 'Record voice message',
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    backgroundColor: isBusy ? Colors.grey : AppColors.primary,
                    child: IconButton(
                      onPressed: isBusy ? null : sendMessage,
                      icon: isBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
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

  Future<void> _sendPushNotification({
    required String messageType,
    required String previewText,
  }) async {
    if (widget.currentUserRole == 'admin') return;

    try {
      await _notificationApi.notifyChatMessage(
        courseId: widget.courseId,
        threadId: widget.threadId,
        senderRole: widget.currentUserRole,
        senderName: widget.senderName,
        messageType: messageType,
        previewText: previewText,
        studentName: _resolvedStudentName,
      );
    } catch (error) {
      debugPrint('Push notification send failed: $error');
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
