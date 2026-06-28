import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ChatUploadException implements Exception {
  final String message;

  const ChatUploadException(this.message);

  @override
  String toString() => message;
}

class FirestoreChatService {
  static const String announcementThreadId = 'announcements';
  static const int maxImageSizeBytes = 5 * 1024 * 1024;
  static const int maxVoiceSizeBytes = 10 * 1024 * 1024;
  static const int maxVideoSizeBytes = 50 * 1024 * 1024;
  static const Set<String> supportedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
  };
  static const Set<String> supportedVideoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
  };
  static const Set<String> supportedVoiceExtensions = {
    'aac',
    'm4a',
    'mp3',
    'ogg',
    'opus',
    'wav',
    'webm',
  };

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static CollectionReference<Map<String, dynamic>> _messagesRef({
    required String courseId,
    required String threadId,
  }) {
    return _db
        .collection('courses')
        .doc(courseId)
        .collection('threads')
        .doc(threadId)
        .collection('messages');
  }

  static CollectionReference<Map<String, dynamic>> _threadsRef({
    required String courseId,
  }) {
    return _db.collection('courses').doc(courseId).collection('threads');
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessages({
    required String courseId,
    required String threadId,
    required int limit,
  }) {
    return _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).orderBy('created_at', descending: true).limit(limit).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getThreads({
    required String courseId,
  }) {
    return _threadsRef(
      courseId: courseId,
    ).orderBy('updated_at', descending: true).snapshots();
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getThread({
    required String courseId,
    required String threadId,
  }) {
    return _threadsRef(courseId: courseId).doc(threadId).snapshots();
  }

  static Stream<int> getTeacherUnreadThreadCount({required String courseId}) {
    return getThreads(courseId: courseId).map(
      (snapshot) => snapshot.docs.where((doc) {
        final unread =
            (doc.data()['teacher_unread_count'] as num?)?.toInt() ?? 0;
        return unread > 0;
      }).length,
    );
  }

  static Stream<int> getStudentUnreadCount({
    required String courseId,
    required String threadId,
  }) {
    return getThread(courseId: courseId, threadId: threadId).map((snapshot) {
      final data = snapshot.data();
      return (data?['student_unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getAnnouncementThread({
    required String courseId,
  }) {
    return getThread(courseId: courseId, threadId: announcementThreadId);
  }

  static Future<void> createOrUpdateThread({
    required String courseId,
    required String threadId,
    required String studentName,
  }) async {
    await _threadsRef(courseId: courseId).doc(threadId).set({
      'thread_id': threadId,
      'student_name': studentName,
      'student_unread_count': 0,
      'teacher_unread_count': 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> createOrUpdateAnnouncementThread({
    required String courseId,
  }) async {
    await _threadsRef(courseId: courseId).doc(announcementThreadId).set({
      'thread_id': announcementThreadId,
      'title': 'Announcement chat',
      'is_announcement': true,
      'pinned': true,
      'student_unread_count': 0,
      'teacher_unread_count': 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> sendTextMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required String text,
    String? studentName,
  }) async {
    final isAnnouncement = threadId == announcementThreadId;
    final threadData = isAnnouncement
        ? _announcementThreadUpdateData(
            senderName: senderName,
            senderRole: senderRole,
            lastMessage: text,
          )
        : _threadUpdateData(
            threadId: threadId,
            senderName: senderName,
            senderRole: senderRole,
            lastMessage: text,
            studentName: studentName,
          );

    await _commitMessage(
      courseId: courseId,
      threadId: threadId,
      threadData: threadData,
      messageData: {
        'type': 'text',
        'text': text,
        'sender_name': senderName,
        'sender_role': senderRole,
        'created_at': FieldValue.serverTimestamp(),
      },
    );
  }

  static Future<void> editTextMessage({
    required String courseId,
    required String threadId,
    required String messageId,
    required String text,
  }) async {
    await _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).doc(messageId).update({
      'text': text.trim(),
      'edited_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteMessage({
    required String courseId,
    required String threadId,
    required String messageId,
    required String deletedByRole,
    required String deletedByName,
  }) async {
    await _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).doc(messageId).update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by_role': deletedByRole,
      'deleted_by_name': deletedByName,
    });
  }

  static Future<void> sendImageMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List imageBytes,
    required String fileName,
    void Function(double progress)? onProgress,
    String? studentName,
  }) async {
    validateImageUpload(fileName: fileName, fileSize: imageBytes.length);
    await _sendMediaMessage(
      courseId: courseId,
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      bytes: imageBytes,
      fileName: fileName,
      type: 'image',
      contentType: _guessImageContentType(fileName),
      lastMessage: 'Photo',
      onProgress: onProgress,
      studentName: studentName,
    );
  }

  static Future<void> sendVideoMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List videoBytes,
    required String fileName,
    int? durationMs,
    void Function(double progress)? onProgress,
    String? studentName,
  }) async {
    validateVideoUpload(fileName: fileName, fileSize: videoBytes.length);
    await _sendMediaMessage(
      courseId: courseId,
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      bytes: videoBytes,
      fileName: fileName,
      type: 'video',
      contentType: _guessVideoContentType(fileName),
      lastMessage: 'Video',
      onProgress: onProgress,
      durationMs: durationMs,
      studentName: studentName,
    );
  }

  static Future<void> sendVoiceMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List voiceBytes,
    required String fileName,
    required int durationMs,
    void Function(double progress)? onProgress,
    String? studentName,
  }) async {
    validateVoiceUpload(fileName: fileName, fileSize: voiceBytes.length);
    await _sendMediaMessage(
      courseId: courseId,
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      bytes: voiceBytes,
      fileName: fileName,
      type: 'voice',
      contentType: _guessVoiceContentType(fileName),
      lastMessage: 'Voice message',
      onProgress: onProgress,
      durationMs: durationMs,
      studentName: studentName,
    );
  }

  static Future<void> _sendMediaMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List bytes,
    required String fileName,
    required String type,
    required String contentType,
    required String lastMessage,
    void Function(double progress)? onProgress,
    int? durationMs,
    String? studentName,
  }) async {
    final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'chat_uploads/courses/$courseId/threads/$threadId/'
        '${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    final uploadTask = _storage
        .ref()
        .child(storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));

    final progressSubscription = onProgress == null
        ? null
        : uploadTask.snapshotEvents.listen((event) {
            final totalBytes = event.totalBytes;
            if (totalBytes <= 0) return;
            onProgress((event.bytesTransferred / totalBytes).clamp(0.0, 1.0));
          });

    late final TaskSnapshot uploadResult;
    try {
      uploadResult = await uploadTask;
    } finally {
      await progressSubscription?.cancel();
    }
    final mediaUrl = await uploadResult.ref.getDownloadURL();

    final isAnnouncement = threadId == announcementThreadId;
    final threadData = isAnnouncement
        ? _announcementThreadUpdateData(
            senderName: senderName,
            senderRole: senderRole,
            lastMessage: lastMessage,
          )
        : _threadUpdateData(
            threadId: threadId,
            senderName: senderName,
            senderRole: senderRole,
            lastMessage: lastMessage,
            studentName: studentName,
          );

    final messageData = <String, dynamic>{
      'type': type,
      'text': '',
      'media_url': mediaUrl,
      'file_name': fileName,
      'storage_path': storagePath,
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (durationMs != null) messageData['duration_ms'] = durationMs;

    await _commitMessage(
      courseId: courseId,
      threadId: threadId,
      threadData: threadData,
      messageData: messageData,
    );
  }

  static void validateImageUpload({
    required String fileName,
    required int fileSize,
  }) {
    final extension = _fileExtension(fileName);

    if (!supportedImageExtensions.contains(extension)) {
      throw const ChatUploadException(
        'Unsupported image format. Choose a JPG, PNG, WEBP, or GIF image.',
      );
    }

    if (fileSize <= 0) {
      throw const ChatUploadException(
        'This image is empty or could not be read.',
      );
    }

    if (fileSize > maxImageSizeBytes) {
      throw const ChatUploadException(
        'This image is larger than 5 MB. Choose a smaller image.',
      );
    }
  }

  static void validateVideoUpload({
    required String fileName,
    required int fileSize,
  }) {
    _validateMediaUpload(
      fileName: fileName,
      fileSize: fileSize,
      supportedExtensions: supportedVideoExtensions,
      maxSizeBytes: maxVideoSizeBytes,
      mediaName: 'video',
      formats: 'MP4, MOV, M4V, or WEBM',
      maxSizeLabel: '50 MB',
    );
  }

  static void validateVoiceUpload({
    required String fileName,
    required int fileSize,
  }) {
    _validateMediaUpload(
      fileName: fileName,
      fileSize: fileSize,
      supportedExtensions: supportedVoiceExtensions,
      maxSizeBytes: maxVoiceSizeBytes,
      mediaName: 'voice recording',
      formats: 'AAC, M4A, MP3, OGG, OPUS, WAV, or WEBM',
      maxSizeLabel: '10 MB',
    );
  }

  static void _validateMediaUpload({
    required String fileName,
    required int fileSize,
    required Set<String> supportedExtensions,
    required int maxSizeBytes,
    required String mediaName,
    required String formats,
    required String maxSizeLabel,
  }) {
    if (!supportedExtensions.contains(_fileExtension(fileName))) {
      throw ChatUploadException(
        'Unsupported $mediaName format. Choose $formats.',
      );
    }
    if (fileSize <= 0) {
      throw ChatUploadException(
        'This $mediaName is empty or could not be read.',
      );
    }
    if (fileSize > maxSizeBytes) {
      throw ChatUploadException(
        'This $mediaName is larger than $maxSizeLabel.',
      );
    }
  }

  static Future<void> _commitMessage({
    required String courseId,
    required String threadId,
    required Map<String, dynamic> threadData,
    required Map<String, dynamic> messageData,
  }) async {
    final threadRef = _threadsRef(courseId: courseId).doc(threadId);
    final messageRef = _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).doc();

    final batch = _db.batch();
    batch.set(threadRef, threadData, SetOptions(merge: true));
    batch.set(messageRef, messageData);

    await batch.commit();
  }

  static Future<void> markThreadRead({
    required String courseId,
    required String threadId,
    required String readerRole,
    String? studentName,
  }) async {
    final prefix = _participantPrefix(readerRole);
    if (prefix == null) return;

    final update = <String, dynamic>{
      'thread_id': threadId,
      '${prefix}_unread_count': 0,
      '${prefix}_last_read_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (studentName != null && studentName.trim().isNotEmpty) {
      update['student_name'] = studentName.trim();
    }

    await _threadsRef(
      courseId: courseId,
    ).doc(threadId).set(update, SetOptions(merge: true));
  }

  static Map<String, dynamic> _threadUpdateData({
    required String threadId,
    required String senderName,
    required String senderRole,
    required String lastMessage,
    String? studentName,
  }) {
    final data = <String, dynamic>{
      'thread_id': threadId,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (senderRole == 'student') {
      data['student_unread_count'] = 0;
      data['student_last_read_at'] = FieldValue.serverTimestamp();
      data['teacher_unread_count'] = FieldValue.increment(1);
    } else if (senderRole == 'teacher') {
      data['teacher_unread_count'] = 0;
      data['teacher_last_read_at'] = FieldValue.serverTimestamp();
      data['student_unread_count'] = FieldValue.increment(1);
    }

    if (studentName != null && studentName.trim().isNotEmpty) {
      data['student_name'] = studentName.trim();
    }

    return data;
  }

  static Map<String, dynamic> _announcementThreadUpdateData({
    required String senderName,
    required String senderRole,
    required String lastMessage,
  }) {
    return {
      'thread_id': announcementThreadId,
      'title': 'Announcement chat',
      'is_announcement': true,
      'pinned': true,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  static String _guessImageContentType(String fileName) {
    final extension = _fileExtension(fileName);

    if (extension == 'png') return 'image/png';
    if (extension == 'webp') return 'image/webp';
    if (extension == 'gif') return 'image/gif';

    return 'image/jpeg';
  }

  static String _guessVideoContentType(String fileName) {
    switch (_fileExtension(fileName)) {
      case 'mov':
        return 'video/quicktime';
      case 'm4v':
        return 'video/x-m4v';
      case 'webm':
        return 'video/webm';
      default:
        return 'video/mp4';
    }
  }

  static String _guessVoiceContentType(String fileName) {
    switch (_fileExtension(fileName)) {
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      case 'webm':
        return 'audio/webm';
      default:
        return 'audio/wav';
    }
  }

  static String _fileExtension(String fileName) {
    final separatorIndex = fileName.lastIndexOf('.');

    if (separatorIndex == -1 || separatorIndex == fileName.length - 1) {
      return '';
    }

    return fileName.substring(separatorIndex + 1).toLowerCase();
  }

  static String? _participantPrefix(String role) {
    switch (role) {
      case 'student':
        return 'student';
      case 'teacher':
        return 'teacher';
      default:
        return null;
    }
  }
}
