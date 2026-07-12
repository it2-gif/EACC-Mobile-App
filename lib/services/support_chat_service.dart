import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/auth_session.dart';

class SupportChatService {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  static CollectionReference<Map<String, dynamic>> get _threadsRef {
    return _db.collection('support_threads');
  }

  static String threadIdFor(AuthSession session) {
    return 'support_${session.appUser.role}_${session.lmsUser.lmsUserId}';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSupportThreads() {
    return _threadsRef.orderBy('updated_at', descending: true).snapshots();
  }

  static Stream<int> getUnreadCount(AuthSession session) {
    if (Firebase.apps.isEmpty) {
      return Stream.value(0);
    }

    if (session.appUser.isTechnicalSupport) {
      return _threadsRef.snapshots().map((snapshot) {
        return snapshot.docs.fold<int>(0, (total, doc) {
          return total +
              ((doc.data()['support_unread_count'] as num?)?.toInt() ?? 0);
        });
      });
    }

    return _threadsRef.doc(threadIdFor(session)).snapshots().map((snapshot) {
      return (snapshot.data()?['user_unread_count'] as num?)?.toInt() ?? 0;
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getThread({
    required String threadId,
  }) {
    return _threadsRef.doc(threadId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getMessages({
    required String threadId,
    int limit = 80,
  }) {
    return _threadsRef
        .doc(threadId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots();
  }

  static Future<void> sendMessage({
    required AuthSession session,
    required String threadId,
    required String text,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final isSupport = session.appUser.isTechnicalSupport;
    final senderRole = isSupport ? 'support' : session.appUser.role;
    final senderName = session.appUser.name;
    final threadRef = _threadsRef.doc(threadId);
    final messageRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final resolvedRequesterName = requesterName?.trim().isNotEmpty == true
        ? requesterName!.trim()
        : session.appUser.name;
    final resolvedRequesterRole = requesterRole?.trim().isNotEmpty == true
        ? requesterRole!.trim()
        : session.appUser.role;
    final resolvedRequesterLmsUserId =
        requesterLmsUserId?.trim().isNotEmpty == true
        ? requesterLmsUserId!.trim()
        : session.lmsUser.lmsUserId;

    final threadData = <String, dynamic>{
      'thread_id': threadId,
      'requester_name': resolvedRequesterName,
      'requester_role': resolvedRequesterRole,
      'requester_lms_user_id': resolvedRequesterLmsUserId,
      'last_message': trimmed,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': now,
      'updated_at': now,
    };

    if (isSupport) {
      threadData['support_unread_count'] = 0;
      threadData['user_unread_count'] = FieldValue.increment(1);
    } else {
      threadData['user_unread_count'] = 0;
      threadData['support_unread_count'] = FieldValue.increment(1);
    }

    final batch = _db.batch();
    batch.set(threadRef, threadData, SetOptions(merge: true));
    batch.set(messageRef, {
      'type': 'text',
      'text': trimmed,
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': now,
    });
    await batch.commit();
  }

  static Future<void> sendImageMessage({
    required AuthSession session,
    required String threadId,
    required Uint8List imageBytes,
    required String fileName,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
    void Function(double progress)? onProgress,
  }) async {
    _validateImageUpload(fileName: fileName, fileSize: imageBytes.length);

    final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final storagePath =
        'support_uploads/threads/$threadId/'
        '${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
    final uploadTask = _storage
        .ref()
        .child(storagePath)
        .putData(
          imageBytes,
          SettableMetadata(contentType: _contentType(fileName)),
        );

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
    await _commitMessage(
      session: session,
      threadId: threadId,
      lastMessage: 'Photo',
      messageData: {
        'type': 'image',
        'text': '',
        'media_url': mediaUrl,
        'file_name': fileName,
        'file_size_bytes': imageBytes.length,
        'file_type': _fileExtension(fileName).toUpperCase(),
        'storage_path': storagePath,
      },
      requesterName: requesterName,
      requesterRole: requesterRole,
      requesterLmsUserId: requesterLmsUserId,
    );
  }

  static Future<void> sendVideoMessage({
    required AuthSession session,
    required String threadId,
    required Uint8List videoBytes,
    required String fileName,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
    void Function(double progress)? onProgress,
  }) async {
    _validateVideoUpload(fileName: fileName, fileSize: videoBytes.length);

    await _sendAttachmentMessage(
      session: session,
      threadId: threadId,
      bytes: videoBytes,
      fileName: fileName,
      type: 'video',
      lastMessage: 'Video',
      requesterName: requesterName,
      requesterRole: requesterRole,
      requesterLmsUserId: requesterLmsUserId,
      onProgress: onProgress,
    );
  }

  static Future<void> sendDocumentMessage({
    required AuthSession session,
    required String threadId,
    required Uint8List documentBytes,
    required String fileName,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
    void Function(double progress)? onProgress,
  }) async {
    _validateDocumentUpload(fileName: fileName, fileSize: documentBytes.length);

    await _sendAttachmentMessage(
      session: session,
      threadId: threadId,
      bytes: documentBytes,
      fileName: fileName,
      type: 'document',
      lastMessage: fileName,
      requesterName: requesterName,
      requesterRole: requesterRole,
      requesterLmsUserId: requesterLmsUserId,
      onProgress: onProgress,
    );
  }

  static Future<void> sendVoiceMessage({
    required AuthSession session,
    required String threadId,
    required Uint8List voiceBytes,
    required String fileName,
    required int durationMs,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
    void Function(double progress)? onProgress,
  }) async {
    _validateVoiceUpload(fileName: fileName, fileSize: voiceBytes.length);

    await _sendAttachmentMessage(
      session: session,
      threadId: threadId,
      bytes: voiceBytes,
      fileName: fileName,
      type: 'voice',
      lastMessage: 'Voice message',
      durationMs: durationMs,
      requesterName: requesterName,
      requesterRole: requesterRole,
      requesterLmsUserId: requesterLmsUserId,
      onProgress: onProgress,
    );
  }

  static Future<void> _sendAttachmentMessage({
    required AuthSession session,
    required String threadId,
    required Uint8List bytes,
    required String fileName,
    required String type,
    required String lastMessage,
    int? durationMs,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
    void Function(double progress)? onProgress,
  }) async {
    final storagePath = _supportStoragePath(threadId, fileName);
    final uploadTask = _storage
        .ref()
        .child(storagePath)
        .putData(bytes, SettableMetadata(contentType: _contentType(fileName)));

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
    final attachmentData = <String, dynamic>{
      'type': type,
      'text': '',
      'media_url': mediaUrl,
      'file_name': fileName,
      'file_size_bytes': bytes.length,
      'file_type': _fileExtension(fileName).toUpperCase(),
      'storage_path': storagePath,
    };
    if (durationMs != null) {
      attachmentData['duration_ms'] = durationMs;
    }

    await _commitMessage(
      session: session,
      threadId: threadId,
      lastMessage: lastMessage,
      messageData: attachmentData,
      requesterName: requesterName,
      requesterRole: requesterRole,
      requesterLmsUserId: requesterLmsUserId,
    );
  }

  static Future<void> _commitMessage({
    required AuthSession session,
    required String threadId,
    required String lastMessage,
    required Map<String, dynamic> messageData,
    String? requesterName,
    String? requesterRole,
    String? requesterLmsUserId,
  }) async {
    final isSupport = session.appUser.isTechnicalSupport;
    final senderRole = isSupport ? 'support' : session.appUser.role;
    final senderName = session.appUser.name;
    final threadRef = _threadsRef.doc(threadId);
    final messageRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final resolvedRequesterName = requesterName?.trim().isNotEmpty == true
        ? requesterName!.trim()
        : session.appUser.name;
    final resolvedRequesterRole = requesterRole?.trim().isNotEmpty == true
        ? requesterRole!.trim()
        : session.appUser.role;
    final resolvedRequesterLmsUserId =
        requesterLmsUserId?.trim().isNotEmpty == true
        ? requesterLmsUserId!.trim()
        : session.lmsUser.lmsUserId;

    final threadData = <String, dynamic>{
      'thread_id': threadId,
      'requester_name': resolvedRequesterName,
      'requester_role': resolvedRequesterRole,
      'requester_lms_user_id': resolvedRequesterLmsUserId,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': now,
      'updated_at': now,
    };

    if (isSupport) {
      threadData['support_unread_count'] = 0;
      threadData['user_unread_count'] = FieldValue.increment(1);
    } else {
      threadData['user_unread_count'] = 0;
      threadData['support_unread_count'] = FieldValue.increment(1);
    }

    final batch = _db.batch();
    batch.set(threadRef, threadData, SetOptions(merge: true));
    batch.set(messageRef, {
      ...messageData,
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': now,
    });
    await batch.commit();
  }

  static Future<void> markRead({
    required AuthSession session,
    required String threadId,
  }) async {
    final isSupport = session.appUser.isTechnicalSupport;
    await _threadsRef.doc(threadId).set({
      'thread_id': threadId,
      isSupport ? 'support_unread_count' : 'user_unread_count': 0,
      isSupport ? 'support_last_read_at' : 'user_last_read_at':
          FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static void _validateImageUpload({
    required String fileName,
    required int fileSize,
  }) {
    final extension = _fileExtension(fileName).toLowerCase();
    const allowed = {'jpg', 'jpeg', 'png', 'gif', 'webp'};
    if (!allowed.contains(extension)) {
      throw ArgumentError('Only JPG, PNG, GIF, and WebP images are supported.');
    }
    if (fileSize > 5 * 1024 * 1024) {
      throw ArgumentError('Image must be 5 MB or smaller.');
    }
  }

  static void _validateVideoUpload({
    required String fileName,
    required int fileSize,
  }) {
    final extension = _fileExtension(fileName).toLowerCase();
    const allowed = {'mp4', 'mov', 'm4v', 'webm'};
    if (!allowed.contains(extension)) {
      throw ArgumentError('Only MP4, MOV, M4V, and WebM videos are supported.');
    }
    if (fileSize > 50 * 1024 * 1024) {
      throw ArgumentError('Video must be 50 MB or smaller.');
    }
  }

  static void _validateDocumentUpload({
    required String fileName,
    required int fileSize,
  }) {
    final extension = _fileExtension(fileName).toLowerCase();
    const allowed = {
      'pdf',
      'doc',
      'docx',
      'ppt',
      'pptx',
      'xls',
      'xlsx',
      'txt',
      'csv',
    };
    if (!allowed.contains(extension)) {
      throw ArgumentError('This document type is not supported.');
    }
    if (fileSize > 20 * 1024 * 1024) {
      throw ArgumentError('Document must be 20 MB or smaller.');
    }
  }

  static void _validateVoiceUpload({
    required String fileName,
    required int fileSize,
  }) {
    final extension = _fileExtension(fileName).toLowerCase();
    const allowed = {'aac', 'm4a', 'mp3', 'ogg', 'opus', 'wav', 'webm'};
    if (!allowed.contains(extension)) {
      throw ArgumentError(
        'Only AAC, M4A, MP3, OGG, OPUS, WAV, and WebM voice files are supported.',
      );
    }
    if (fileSize <= 0) {
      throw ArgumentError(
        'This voice recording is empty or could not be read.',
      );
    }
    if (fileSize > 10 * 1024 * 1024) {
      throw ArgumentError('Voice recording must be 10 MB or smaller.');
    }
  }

  static String _contentType(String fileName) {
    return switch (_fileExtension(fileName).toLowerCase()) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'aac' => 'audio/aac',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      _ => 'application/octet-stream',
    };
  }

  static String _supportStoragePath(String threadId, String fileName) {
    final safeFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return 'support_uploads/threads/$threadId/'
        '${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
  }

  static String _fileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last : '';
  }
}
