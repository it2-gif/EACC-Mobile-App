import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../models/auth_session.dart';
import '../services/support_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/message_bubble.dart';
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
  final audioRecorder = AudioRecorder();
  final voiceChunks = <Uint8List>[];
  bool isSending = false;
  bool isUploadingMedia = false;
  bool isRecordingVoice = false;
  bool isVoiceRecordingPaused = false;
  double uploadProgress = 0;
  Duration recordingDuration = Duration.zero;
  Timer? recordingTimer;
  StreamSubscription<Uint8List>? recordingSubscription;
  int recordingSampleRate = 16000;

  late final String threadId =
      widget.threadId ?? SupportChatService.threadIdFor(widget.session);

  bool get isSupportUser => widget.session.appUser.isTechnicalSupport;

  @override
  void dispose() {
    recordingTimer?.cancel();
    recordingSubscription?.cancel();
    audioRecorder.dispose();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || isSending || isUploadingMedia || isRecordingVoice) {
      return;
    }

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

  void showAttachmentOptions() {
    if (isSending || isUploadingMedia || isRecordingVoice) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                _SupportAttachmentOption(
                  icon: Icons.photo_camera_rounded,
                  title: 'Take photo',
                  subtitle: 'Capture and send an image',
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendImage(ImageSource.camera);
                  },
                ),
                _SupportAttachmentOption(
                  icon: Icons.image_rounded,
                  title: 'Choose image',
                  subtitle: 'Send a photo from this device',
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendImage(ImageSource.gallery);
                  },
                ),
                _SupportAttachmentOption(
                  icon: Icons.videocam_rounded,
                  title: 'Send video',
                  subtitle: 'Upload a short support video',
                  onTap: () {
                    Navigator.pop(context);
                    pickAndSendVideo();
                  },
                ),
                _SupportAttachmentOption(
                  icon: Icons.description_rounded,
                  title: 'Send document',
                  subtitle: 'PDF, Word, Excel, PowerPoint, TXT, CSV',
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

  Future<void> pickAndSendImage(ImageSource source) async {
    if (isSending || isUploadingMedia || isRecordingVoice) return;

    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image == null) return;

    setState(() {
      isUploadingMedia = true;
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
          isUploadingMedia = false;
          uploadProgress = 0;
        });
      }
    }
  }

  Future<void> pickAndSendVideo() async {
    if (isSending || isUploadingMedia || isRecordingVoice) return;

    final video = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (video == null) return;

    setState(() {
      isUploadingMedia = true;
      uploadProgress = 0;
    });

    try {
      final videoBytes = await video.readAsBytes();
      await SupportChatService.sendVideoMessage(
        session: widget.session,
        threadId: threadId,
        videoBytes: videoBytes,
        fileName: video.name,
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
      ).showSnackBar(SnackBar(content: Text('Could not upload video: $error')));
    } finally {
      if (mounted) {
        setState(() {
          isUploadingMedia = false;
          uploadProgress = 0;
        });
      }
    }
  }

  Future<void> pickAndSendDocument() async {
    if (isSending || isUploadingMedia || isRecordingVoice) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf',
        'doc',
        'docx',
        'ppt',
        'pptx',
        'xls',
        'xlsx',
        'txt',
        'csv',
      ],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read the selected document.')),
      );
      return;
    }

    setState(() {
      isUploadingMedia = true;
      uploadProgress = 0;
    });

    try {
      await SupportChatService.sendDocumentMessage(
        session: widget.session,
        threadId: threadId,
        documentBytes: bytes,
        fileName: file.name,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload document: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploadingMedia = false;
          uploadProgress = 0;
        });
      }
    }
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
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
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
        if (!mounted || isVoiceRecordingPaused) return;
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
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      final isPermissionError =
          message.contains('permission') ||
          message.contains('notallowed') ||
          message.contains('not allowed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPermissionError
                ? 'Microphone access is blocked. Allow it, then try again.'
                : 'Could not start voice recording: $error',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
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
        uploadProgress = 0;
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
        throw ArgumentError(
          'No voice was detected. Check the selected microphone and try again.',
        );
      }

      await SupportChatService.sendVoiceMessage(
        session: widget.session,
        threadId: threadId,
        voiceBytes: voiceBytes,
        fileName: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
        durationMs: recordingDuration.inMilliseconds,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send voice message: $error')),
      );
    } finally {
      voiceChunks.clear();
      if (mounted) {
        setState(() {
          isUploadingMedia = false;
          uploadProgress = 0;
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
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final senderName = data['sender_name']?.toString() ?? '';
                      final senderRole = data['sender_role']?.toString() ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: MessageBubble(
                          text: data['text']?.toString() ?? '',
                          type: data['type']?.toString() ?? 'text',
                          mediaUrl: data['media_url']?.toString(),
                          fileName: data['file_name']?.toString(),
                          fileSizeBytes: (data['file_size_bytes'] as num?)
                              ?.toInt(),
                          fileType: data['file_type']?.toString(),
                          durationMs: (data['duration_ms'] as num?)?.toInt(),
                          senderName: senderName,
                          senderRole: senderRole,
                          currentUserRole: isSupportUser
                              ? 'support'
                              : widget.session.appUser.role,
                          currentSenderName: widget.session.appUser.name,
                          createdAt: data['created_at'],
                          editedAt: null,
                          deletedAt: null,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            _SupportInputBar(
              controller: messageController,
              isSending: isSending || isUploadingMedia,
              isRecordingVoice: isRecordingVoice,
              isVoiceRecordingPaused: isVoiceRecordingPaused,
              recordingDuration: _formatRecordingDuration(),
              uploadProgress: isUploadingMedia ? uploadProgress : null,
              onAttach: showAttachmentOptions,
              onSend: sendMessage,
              onToggleVoiceRecording: toggleVoiceRecording,
              onToggleVoiceRecordingPause: toggleVoiceRecordingPause,
              onCancelVoiceRecording: cancelVoiceRecording,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRecordingDuration() {
    final minutes = recordingDuration.inMinutes;
    final seconds = recordingDuration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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

class _SupportAttachmentOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SupportAttachmentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _SupportInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isRecordingVoice;
  final bool isVoiceRecordingPaused;
  final String recordingDuration;
  final double? uploadProgress;
  final VoidCallback onAttach;
  final VoidCallback onSend;
  final VoidCallback onToggleVoiceRecording;
  final VoidCallback onToggleVoiceRecordingPause;
  final VoidCallback onCancelVoiceRecording;

  const _SupportInputBar({
    required this.controller,
    required this.isSending,
    required this.isRecordingVoice,
    required this.isVoiceRecordingPaused,
    required this.recordingDuration,
    required this.uploadProgress,
    required this.onAttach,
    required this.onSend,
    required this.onToggleVoiceRecording,
    required this.onToggleVoiceRecordingPause,
    required this.onCancelVoiceRecording,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
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
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  onPressed: isRecordingVoice
                      ? onCancelVoiceRecording
                      : isSending
                      ? null
                      : onAttach,
                  style: IconButton.styleFrom(
                    foregroundColor: isRecordingVoice ? AppColors.danger : null,
                  ),
                  icon: Icon(
                    isRecordingVoice
                        ? Icons.delete_outline_rounded
                        : Icons.add_rounded,
                  ),
                  tooltip: isRecordingVoice
                      ? 'Cancel recording'
                      : 'Add attachment',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isRecordingVoice
                      ? _SupportRecordingComposerPill(
                          duration: recordingDuration,
                          isPaused: isVoiceRecordingPaused,
                          onTogglePause: onToggleVoiceRecordingPause,
                        )
                      : TextField(
                          controller: controller,
                          enabled: !isSending,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: uploadProgress != null
                                ? 'Uploading media...'
                                : 'Write a message',
                            filled: true,
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                ),
                const SizedBox(width: 8),
                if (!isRecordingVoice) ...[
                  IconButton.filledTonal(
                    onPressed: isSending ? null : onToggleVoiceRecording,
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.mic_none_rounded),
                    tooltip: 'Record voice message',
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: isSending
                      ? null
                      : isRecordingVoice
                      ? onToggleVoiceRecording
                      : onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.square(50),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
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

class _SupportRecordingComposerPill extends StatelessWidget {
  final String duration;
  final bool isPaused;
  final VoidCallback onTogglePause;

  const _SupportRecordingComposerPill({
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
