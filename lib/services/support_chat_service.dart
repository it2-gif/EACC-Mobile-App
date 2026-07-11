import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/auth_session.dart';

class SupportChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _threadsRef {
    return _db.collection('support_threads');
  }

  static String threadIdFor(AuthSession session) {
    return 'support_${session.appUser.role}_${session.lmsUser.lmsUserId}';
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getSupportThreads() {
    return _threadsRef.orderBy('updated_at', descending: true).snapshots();
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

    final resolvedRequesterName =
        requesterName?.trim().isNotEmpty == true
        ? requesterName!.trim()
        : session.appUser.name;
    final resolvedRequesterRole =
        requesterRole?.trim().isNotEmpty == true
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

}
