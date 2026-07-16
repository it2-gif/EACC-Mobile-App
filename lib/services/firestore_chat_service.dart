import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'chat_thread_resolver.dart';

class ChatUploadException implements Exception {
  final String message;

  const ChatUploadException(this.message);

  @override
  String toString() => message;
}

class MessageReply {
  final String messageId;
  final String senderName;
  final String senderRole;
  final String type;
  final String preview;

  const MessageReply({
    required this.messageId,
    required this.senderName,
    required this.senderRole,
    required this.type,
    required this.preview,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'reply_to_message_id': messageId,
      'reply_to_sender_name': senderName,
      'reply_to_sender_role': senderRole,
      'reply_to_type': type,
      'reply_to_preview': preview,
    };
  }
}

class CourseActivitySummary {
  final int messages;
  final int images;
  final int videos;
  final int documents;
  final int voiceMessages;

  const CourseActivitySummary({
    required this.messages,
    required this.images,
    required this.videos,
    required this.documents,
    required this.voiceMessages,
  });

  int get uploads => images + videos + documents;
}

class ApplicationActivitySummary {
  final int chats;
  final int messages;
  final int images;
  final int videos;
  final int documents;
  final int voiceMessages;
  final int uploadedBytes;

  const ApplicationActivitySummary({
    required this.chats,
    required this.messages,
    required this.images,
    required this.videos,
    required this.documents,
    required this.voiceMessages,
    required this.uploadedBytes,
  });

  int get uploads => images + videos + documents;
  int get storageItems => images + videos + documents + voiceMessages;
}

class AdminInboxPage {
  final List<AdminInboxThread> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const AdminInboxPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });
}

class AdminInboxThread {
  final String courseId;
  final String threadId;
  final String title;
  final String studentName;
  final String lastMessage;
  final String lastSenderName;
  final String lastSenderRole;
  final Timestamp? lastMessageAt;
  final int adminUnreadCount;
  final Map<String, dynamic> data;

  const AdminInboxThread({
    required this.courseId,
    required this.threadId,
    required this.title,
    required this.studentName,
    required this.lastMessage,
    required this.lastSenderName,
    required this.lastSenderRole,
    required this.lastMessageAt,
    required this.adminUnreadCount,
    required this.data,
  });

  bool get isAnnouncement =>
      threadId == ChatThreadResolver.announcementThreadId;
  bool get isTeacherChat => threadId == ChatThreadResolver.adminTeacherThreadId;
  bool get isContactPersonChat =>
      ChatThreadResolver.isStudentContactPersonThreadId(threadId);
  bool get isStudentTeacherChat =>
      !isAnnouncement && !isTeacherChat && !isContactPersonChat;
}

class FirestoreChatService {
  static const int maxImageSizeBytes = 5 * 1024 * 1024;
  static const int maxVoiceSizeBytes = 10 * 1024 * 1024;
  static const int maxDocumentSizeBytes = 25 * 1024 * 1024;
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
  static const Set<String> supportedDocumentExtensions = {
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

  static Stream<List<DocumentSnapshot<Map<String, dynamic>>>>
  getThreadDocuments({
    required String courseId,
    required Iterable<String> threadIds,
  }) {
    final normalizedCourseId = courseId.trim();
    final ids = threadIds
        .map((threadId) => threadId.trim())
        .where((threadId) => threadId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (normalizedCourseId.isEmpty || ids.isEmpty) {
      return Stream.value(<DocumentSnapshot<Map<String, dynamic>>>[]);
    }

    return Stream<List<DocumentSnapshot<Map<String, dynamic>>>>.multi((
      controller,
    ) {
      final docsById = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      final seenIds = <String>{};
      final subscriptions = <StreamSubscription<dynamic>>[];
      var closed = false;

      void emitWhenReady() {
        if (closed || seenIds.length != ids.length) return;

        controller.add(
          ids
              .map((id) => docsById[id])
              .whereType<DocumentSnapshot<Map<String, dynamic>>>()
              .toList(growable: false),
        );
      }

      for (final threadId in ids) {
        final subscription =
            getThread(courseId: normalizedCourseId, threadId: threadId).listen((
              snapshot,
            ) {
              seenIds.add(threadId);
              docsById[threadId] = snapshot;
              emitWhenReady();
            }, onError: controller.addError);
        subscriptions.add(subscription);
      }

      controller.onCancel = () async {
        closed = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  static Stream<int> getTeacherUnreadMessageCount({
    required String courseId,
    required Iterable<String> studentThreadIds,
  }) {
    return _combineThreadUnreadStreams(
      courseIds: [courseId],
      threadIds: studentThreadIds,
      unreadField: 'teacher_unread_count',
    );
  }

  static Stream<AdminUnreadCounts> getAdminUnreadCounts({
    required String courseId,
  }) {
    return getThreads(courseId: courseId).map((snapshot) {
      int teacherUnread = 0;
      int studentUnread = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final threadId = doc.id;
        final unread = readUnreadCount(data, 'admin_unread_count');
        if (unread > 0) {
          if (threadId == ChatThreadResolver.adminTeacherThreadId) {
            teacherUnread += unread;
          } else if (ChatThreadResolver.isStudentContactPersonThreadId(
            threadId,
          )) {
            studentUnread += unread;
          }
        }
      }

      return AdminUnreadCounts(
        teacherUnread: teacherUnread,
        studentUnread: studentUnread,
      );
    });
  }

  static Stream<int> getAdminUnreadTotalForCourses(Iterable<String> courseIds) {
    return _combineCourseUnreadStreams(
      courseIds: courseIds,
      readCount: (data, threadId) {
        if (threadId != ChatThreadResolver.adminTeacherThreadId &&
            !ChatThreadResolver.isStudentContactPersonThreadId(threadId)) {
          return 0;
        }
        return readUnreadCount(data, 'admin_unread_count');
      },
    );
  }

  static Stream<int> getAdminUnreadCount({
    required String courseId,
    required String threadId,
  }) {
    return getThreadUnreadCount(
      courseId: courseId,
      threadId: threadId,
      unreadField: 'admin_unread_count',
    );
  }

  static Stream<int> getThreadUnreadCount({
    required String courseId,
    required String threadId,
    required String unreadField,
  }) {
    return getThread(courseId: courseId, threadId: threadId).map((snapshot) {
      return readUnreadCount(snapshot.data(), unreadField);
    });
  }

  static int readTeacherUnreadCount(Map<String, dynamic>? data) {
    return readUnreadCount(data, 'teacher_unread_count');
  }

  static int readUnreadCount(Map<String, dynamic>? data, String unreadField) {
    return (data?[unreadField] as num?)?.toInt() ?? 0;
  }

  static int readStudentUnreadCount(Map<String, dynamic>? data) {
    return readUnreadCount(data, 'student_unread_count');
  }

  static Stream<int> getStudentUnreadTotalForCourses({
    required Iterable<String> courseIds,
    required String studentThreadId,
  }) {
    final normalizedThreadId = studentThreadId.trim();
    final keyPersonThreadId = ChatThreadResolver.studentContactPersonThreadId(
      normalizedThreadId,
    );

    return _combineThreadUnreadStreams(
      courseIds: courseIds,
      threadIds: [normalizedThreadId, keyPersonThreadId],
      unreadField: 'student_unread_count',
    );
  }

  static Stream<int> _combineThreadUnreadStreams({
    required Iterable<String> courseIds,
    required Iterable<String> threadIds,
    required String unreadField,
  }) {
    final courseIdList = courseIds
        .map((courseId) => courseId.trim())
        .where((courseId) => courseId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final threadIdList = threadIds
        .map((threadId) => threadId.trim())
        .where((threadId) => threadId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (courseIdList.isEmpty || threadIdList.isEmpty) {
      return Stream.value(0);
    }

    return Stream<int>.multi((controller) {
      final totalsByThread = <String, int>{};
      final subscriptions = <StreamSubscription<dynamic>>[];
      var closed = false;

      void emitTotal() {
        if (!closed) {
          controller.add(totalsByThread.values.fold<int>(0, (a, b) => a + b));
        }
      }

      for (final courseId in courseIdList) {
        for (final threadId in threadIdList) {
          final key = '$courseId/$threadId';
          totalsByThread[key] = 0;

          final subscription = getThread(courseId: courseId, threadId: threadId)
              .listen((snapshot) {
                totalsByThread[key] = readUnreadCount(
                  snapshot.data(),
                  unreadField,
                );
                emitTotal();
              }, onError: controller.addError);
          subscriptions.add(subscription);
        }
      }

      emitTotal();

      controller.onCancel = () async {
        closed = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  static Stream<int> _combineCourseUnreadStreams({
    required Iterable<String> courseIds,
    required int Function(Map<String, dynamic> data, String threadId) readCount,
  }) {
    final ids = courseIds
        .map((courseId) => courseId.trim())
        .where((courseId) => courseId.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ids.isEmpty) return Stream.value(0);

    return Stream<int>.multi((controller) {
      final totalsByCourse = <String, int>{for (final id in ids) id: 0};
      final subscriptions = <StreamSubscription<dynamic>>[];
      var closed = false;

      void emitTotal() {
        if (!closed) {
          controller.add(totalsByCourse.values.fold<int>(0, (a, b) => a + b));
        }
      }

      for (final courseId in ids) {
        final subscription = getThreads(courseId: courseId).listen((snapshot) {
          var total = 0;
          for (final doc in snapshot.docs) {
            total += readCount(doc.data(), doc.id);
          }
          totalsByCourse[courseId] = total;
          emitTotal();
        }, onError: controller.addError);
        subscriptions.add(subscription);
      }

      controller.onCancel = () async {
        closed = true;
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> getAnnouncementThread({
    required String courseId,
  }) {
    return getThread(
      courseId: courseId,
      threadId: ChatThreadResolver.announcementThreadId,
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getRecentCourseMessagesForModeration({
    required String courseId,
    int maxThreads = 20,
    int messagesPerThread = 5,
    int limit = 100,
  }) async {
    final normalizedCourseId = courseId.trim();
    if (normalizedCourseId.isEmpty) return [];

    final threadSnapshot = await _threadsRef(
      courseId: normalizedCourseId,
    ).orderBy('updated_at', descending: true).limit(maxThreads).get();

    final messageSnapshots = await Future.wait(
      threadSnapshot.docs.map((thread) {
        return thread.reference
            .collection('messages')
            .orderBy('created_at', descending: true)
            .limit(messagesPerThread)
            .get();
      }),
    );

    final docs = messageSnapshots
        .expand((snapshot) => snapshot.docs)
        .toList(growable: false);

    final sortedDocs = [...docs]
      ..sort((a, b) {
        final aTime = a.data()['created_at'];
        final bTime = b.data()['created_at'];
        final aDate = aTime is Timestamp
            ? aTime.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = bTime is Timestamp
            ? bTime.toDate()
            : DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    return sortedDocs.take(limit).toList(growable: false);
  }

  static Future<CourseActivitySummary> getCourseActivitySummary({
    required String courseId,
    int maxThreads = 80,
    int messagesPerThread = 50,
  }) async {
    final docs = await getRecentCourseMessagesForModeration(
      courseId: courseId,
      maxThreads: maxThreads,
      messagesPerThread: messagesPerThread,
      limit: maxThreads * messagesPerThread,
    );

    var images = 0;
    var videos = 0;
    var documents = 0;
    var voiceMessages = 0;

    for (final doc in docs) {
      switch (doc.data()['type']?.toString()) {
        case 'image':
          images++;
          break;
        case 'video':
          videos++;
          break;
        case 'document':
          documents++;
          break;
        case 'voice':
          voiceMessages++;
          break;
      }
    }

    return CourseActivitySummary(
      messages: docs.length,
      images: images,
      videos: videos,
      documents: documents,
      voiceMessages: voiceMessages,
    );
  }

  static Future<ApplicationActivitySummary> getApplicationActivitySummary({
    required Iterable<String> courseIds,
  }) async {
    var chats = 0;
    var messages = 0;
    var images = 0;
    var videos = 0;
    var documents = 0;
    var voiceMessages = 0;
    var uploadedBytes = 0;

    final uniqueCourseIds = courseIds
        .map((courseId) => courseId.trim())
        .where((courseId) => courseId.isNotEmpty)
        .toSet();

    for (final courseId in uniqueCourseIds) {
      final threadSnapshot = await _threadsRef(courseId: courseId).get();
      chats += threadSnapshot.docs.length;

      for (final thread in threadSnapshot.docs) {
        final messagesRef = thread.reference.collection('messages');
        messages += await _countQuery(messagesRef);
        images += await _countQuery(
          messagesRef.where('type', isEqualTo: 'image'),
        );
        videos += await _countQuery(
          messagesRef.where('type', isEqualTo: 'video'),
        );
        documents += await _countQuery(
          messagesRef.where('type', isEqualTo: 'document'),
        );
        voiceMessages += await _countQuery(
          messagesRef.where('type', isEqualTo: 'voice'),
        );
        uploadedBytes += await _sumFileSizeBytes(
          messagesRef.where('type', isEqualTo: 'image'),
        );
        uploadedBytes += await _sumFileSizeBytes(
          messagesRef.where('type', isEqualTo: 'video'),
        );
        uploadedBytes += await _sumFileSizeBytes(
          messagesRef.where('type', isEqualTo: 'document'),
        );
        uploadedBytes += await _sumFileSizeBytes(
          messagesRef.where('type', isEqualTo: 'voice'),
        );
      }
    }

    return ApplicationActivitySummary(
      chats: chats,
      messages: messages,
      images: images,
      videos: videos,
      documents: documents,
      voiceMessages: voiceMessages,
      uploadedBytes: uploadedBytes,
    );
  }

  static Future<AdminInboxPage> getAdminInboxPage({
    int pageSize = 5,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collectionGroup('threads')
        .orderBy('last_message_at', descending: true)
        .limit(pageSize + 1);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final visibleDocs = snapshot.docs.take(pageSize).toList(growable: false);

    return AdminInboxPage(
      items: visibleDocs
          .map(_adminInboxThreadFromDoc)
          .where((thread) => thread.lastMessage.trim().isNotEmpty)
          .toList(growable: false),
      cursor: visibleDocs.isEmpty ? startAfter : visibleDocs.last,
      hasMore: snapshot.docs.length > pageSize,
    );
  }

  static AdminInboxThread _adminInboxThreadFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final courseRef = doc.reference.parent.parent;
    final threadId = (data['thread_id']?.toString().trim().isNotEmpty ?? false)
        ? data['thread_id'].toString().trim()
        : doc.id;
    final title = data['title']?.toString().trim();
    final studentName = data['student_name']?.toString().trim() ?? '';
    final lastMessageAt = data['last_message_at'];

    return AdminInboxThread(
      courseId: courseRef?.id ?? '',
      threadId: threadId,
      title: title == null || title.isEmpty ? threadId : title,
      studentName: studentName,
      lastMessage: data['last_message']?.toString() ?? '',
      lastSenderName: data['last_sender_name']?.toString() ?? 'Unknown',
      lastSenderRole: data['last_sender_role']?.toString() ?? 'user',
      lastMessageAt: lastMessageAt is Timestamp ? lastMessageAt : null,
      adminUnreadCount: readUnreadCount(data, 'admin_unread_count'),
      data: data,
    );
  }

  static Future<int> _countQuery(Query<Map<String, dynamic>> query) async {
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  }

  static Future<int> _sumFileSizeBytes(
    Query<Map<String, dynamic>> query,
  ) async {
    final snapshot = await query.get();
    var total = 0;

    for (final doc in snapshot.docs) {
      total += (doc.data()['file_size_bytes'] as num?)?.toInt() ?? 0;
    }

    return total;
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> getAuditLogs({
    int limit = 100,
  }) {
    return _db
        .collection('audit_logs')
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots();
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
    await _threadsRef(
      courseId: courseId,
    ).doc(ChatThreadResolver.announcementThreadId).set({
      'thread_id': ChatThreadResolver.announcementThreadId,
      'title': 'Announcement chat',
      'is_announcement': true,
      'pinned': true,
      'student_unread_count': 0,
      'teacher_unread_count': 0,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> setAnnouncementPinned({
    required String courseId,
    required bool pinned,
  }) async {
    await _threadsRef(
      courseId: courseId,
    ).doc(ChatThreadResolver.announcementThreadId).set({
      'thread_id': ChatThreadResolver.announcementThreadId,
      'title': 'Announcement chat',
      'is_announcement': true,
      'pinned': pinned,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> markAnnouncementRead({
    required String courseId,
    required String readerRole,
    required String readerName,
  }) async {
    if (readerRole != 'student') return;

    final user = FirebaseAuth.instance.currentUser;
    final normalizedName = readerName.trim();
    if (user == null || normalizedName.isEmpty) return;

    final threadRef = _threadsRef(
      courseId: courseId,
    ).doc(ChatThreadResolver.announcementThreadId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(threadRef);
      if (!snapshot.exists) return;

      final currentReads = snapshot.data()?['announcement_reads'];
      final nextReads = <String, dynamic>{};
      if (currentReads is Map) {
        for (final entry in currentReads.entries) {
          nextReads[entry.key.toString()] = entry.value;
        }
      }

      nextReads[user.uid] = {
        'role': readerRole,
        'display_name': normalizedName,
        'read_at': FieldValue.serverTimestamp(),
      };

      transaction.update(threadRef, {
        'thread_id': ChatThreadResolver.announcementThreadId,
        'is_announcement': true,
        'announcement_reads': nextReads,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  static int announcementStudentReadCount(dynamic reads) {
    if (reads is! Map) return 0;

    return reads.entries.where((entry) {
      final value = entry.value;
      if (value is Map) {
        return value['role']?.toString().toLowerCase() == 'student';
      }
      return entry.key.toString().toLowerCase().startsWith('student_');
    }).length;
  }

  static Future<void> setTypingState({
    required String courseId,
    required String threadId,
    required String senderRole,
    required String senderName,
    required bool isTyping,
  }) async {
    await _threadsRef(courseId: courseId).doc(threadId).set({
      'thread_id': threadId,
      'typing_active': isTyping,
      'typing_role': senderRole,
      'typing_name': senderName,
      'typing_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> logAuditEvent({
    required String actorRole,
    required String actorName,
    required String action,
    required String resourceType,
    required String resourceId,
    Map<String, dynamic>? metadata,
  }) async {
    await _db.collection('audit_logs').add({
      'actor_role': actorRole,
      'actor_name': actorName,
      'action': action,
      'resource_type': resourceType,
      'resource_id': resourceId,
      'metadata': metadata ?? <String, dynamic>{},
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  static Future<String> sendTextMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required String text,
    String? studentName,
    MessageReply? reply,
  }) async {
    final threadData = _messageThreadUpdateData(
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      lastMessage: text,
      studentName: studentName,
    );

    final messageData = <String, dynamic>{
      'type': 'text',
      'text': text,
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (reply != null) messageData.addAll(reply.toFirestore());

    return _commitMessage(
      courseId: courseId,
      threadId: threadId,
      threadData: threadData,
      messageData: messageData,
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

  static Future<void> deleteMessageByReference({
    required DocumentReference<Map<String, dynamic>> messageRef,
    required String deletedByRole,
    required String deletedByName,
  }) async {
    await messageRef.update({
      'deleted_at': FieldValue.serverTimestamp(),
      'deleted_by_role': deletedByRole,
      'deleted_by_name': deletedByName,
    });
  }

  static Future<void> setMessagePinned({
    required String courseId,
    required String threadId,
    required String messageId,
    required bool pinned,
    required String pinnedByRole,
    required String pinnedByName,
  }) async {
    final update = <String, dynamic>{
      'pinned': pinned,
      'pinned_at': pinned ? FieldValue.serverTimestamp() : FieldValue.delete(),
      'pinned_by_role': pinned ? pinnedByRole : FieldValue.delete(),
      'pinned_by_name': pinned ? pinnedByName : FieldValue.delete(),
    };

    await _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).doc(messageId).update(update);
  }

  static Future<void> toggleReaction({
    required String courseId,
    required String threadId,
    required String messageId,
    required String emoji,
    required String reactorRole,
    required String reactorName,
  }) async {
    final reactorKey = '$reactorRole:$reactorName';
    final messageRef = _messagesRef(
      courseId: courseId,
      threadId: threadId,
    ).doc(messageId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(messageRef);
      final data = snapshot.data();
      final reactions = data?['reactions'];
      final existing = reactions is Map
          ? List<String>.from(reactions[emoji] as List? ?? const [])
          : <String>[];
      final hasReacted = existing.contains(reactorKey);

      transaction.update(messageRef, {
        'reactions.$emoji': hasReacted
            ? FieldValue.arrayRemove([reactorKey])
            : FieldValue.arrayUnion([reactorKey]),
      });
    });
  }

  static Future<String> sendImageMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List imageBytes,
    required String fileName,
    void Function(double progress)? onProgress,
    String? studentName,
    MessageReply? reply,
  }) async {
    validateImageUpload(fileName: fileName, fileSize: imageBytes.length);
    return _sendMediaMessage(
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
      reply: reply,
    );
  }

  static Future<String> sendVideoMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List videoBytes,
    required String fileName,
    int? durationMs,
    void Function(double progress)? onProgress,
    String? studentName,
    MessageReply? reply,
  }) async {
    validateVideoUpload(fileName: fileName, fileSize: videoBytes.length);
    return _sendMediaMessage(
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
      reply: reply,
    );
  }

  static Future<String> sendVoiceMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List voiceBytes,
    required String fileName,
    required int durationMs,
    void Function(double progress)? onProgress,
    String? studentName,
    MessageReply? reply,
  }) async {
    validateVoiceUpload(fileName: fileName, fileSize: voiceBytes.length);
    return _sendMediaMessage(
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
      reply: reply,
    );
  }

  static Future<String> sendDocumentMessage({
    required String courseId,
    required String threadId,
    required String senderName,
    required String senderRole,
    required Uint8List documentBytes,
    required String fileName,
    void Function(double progress)? onProgress,
    String? studentName,
    MessageReply? reply,
  }) async {
    validateDocumentUpload(fileName: fileName, fileSize: documentBytes.length);
    return _sendMediaMessage(
      courseId: courseId,
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      bytes: documentBytes,
      fileName: fileName,
      type: 'document',
      contentType: _guessDocumentContentType(fileName),
      lastMessage: 'Document',
      onProgress: onProgress,
      studentName: studentName,
      reply: reply,
    );
  }

  static Future<String> forwardMessage({
    required String courseId,
    required String targetThreadId,
    required String senderName,
    required String senderRole,
    required Map<String, dynamic> sourceData,
    String? studentName,
  }) async {
    final type = sourceData['type']?.toString() ?? 'text';
    final preview = _forwardPreview(sourceData);
    final threadData = _messageThreadUpdateData(
      threadId: targetThreadId,
      senderName: senderName,
      senderRole: senderRole,
      lastMessage: preview,
      studentName: studentName,
    );

    final messageData = <String, dynamic>{
      'type': type,
      'text': sourceData['text']?.toString() ?? '',
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': FieldValue.serverTimestamp(),
      'forwarded': true,
      'forwarded_from_sender_name': sourceData['sender_name']?.toString() ?? '',
      'forwarded_from_sender_role': sourceData['sender_role']?.toString() ?? '',
    };

    for (final key in [
      'media_url',
      'file_name',
      'duration_ms',
      'file_size_bytes',
      'file_type',
    ]) {
      if (sourceData[key] != null) messageData[key] = sourceData[key];
    }

    return _commitMessage(
      courseId: courseId,
      threadId: targetThreadId,
      threadData: threadData,
      messageData: messageData,
    );
  }

  static Future<String> _sendMediaMessage({
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
    MessageReply? reply,
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

    final threadData = _messageThreadUpdateData(
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
      'file_size_bytes': bytes.length,
      'file_type': _fileExtension(fileName).toUpperCase(),
      'storage_path': storagePath,
      'sender_name': senderName,
      'sender_role': senderRole,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (durationMs != null) messageData['duration_ms'] = durationMs;
    if (reply != null) messageData.addAll(reply.toFirestore());

    return _commitMessage(
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

  static void validateDocumentUpload({
    required String fileName,
    required int fileSize,
  }) {
    _validateMediaUpload(
      fileName: fileName,
      fileSize: fileSize,
      supportedExtensions: supportedDocumentExtensions,
      maxSizeBytes: maxDocumentSizeBytes,
      mediaName: 'document',
      formats: 'PDF, DOC, DOCX, PPT, PPTX, XLS, XLSX, TXT, or CSV',
      maxSizeLabel: '25 MB',
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

  static Future<String> _commitMessage({
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
    return messageRef.id;
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

  static Map<String, dynamic> _messageThreadUpdateData({
    required String threadId,
    required String senderName,
    required String senderRole,
    required String lastMessage,
    String? studentName,
  }) {
    if (threadId == ChatThreadResolver.announcementThreadId) {
      return _announcementThreadUpdateData(
        senderName: senderName,
        senderRole: senderRole,
        lastMessage: lastMessage,
      );
    }

    if (threadId == ChatThreadResolver.adminTeacherThreadId) {
      return _adminTeacherThreadUpdateData(
        senderName: senderName,
        senderRole: senderRole,
        lastMessage: lastMessage,
      );
    }

    if (ChatThreadResolver.isStudentContactPersonThreadId(threadId)) {
      return _keyPersonStudentThreadUpdateData(
        threadId: threadId,
        senderName: senderName,
        senderRole: senderRole,
        lastMessage: lastMessage,
        studentName: studentName,
      );
    }

    return _threadUpdateData(
      threadId: threadId,
      senderName: senderName,
      senderRole: senderRole,
      lastMessage: lastMessage,
      studentName: studentName,
    );
  }

  static Map<String, dynamic> _announcementThreadUpdateData({
    required String senderName,
    required String senderRole,
    required String lastMessage,
  }) {
    return {
      'thread_id': ChatThreadResolver.announcementThreadId,
      'title': 'Announcement chat',
      'is_announcement': true,
      'pinned': true,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': FieldValue.serverTimestamp(),
      'announcement_reads': <String, dynamic>{},
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  static Map<String, dynamic> _adminTeacherThreadUpdateData({
    required String senderName,
    required String senderRole,
    required String lastMessage,
  }) {
    final data = <String, dynamic>{
      'thread_id': ChatThreadResolver.adminTeacherThreadId,
      'title': 'EACC Admin',
      'is_admin_teacher': true,
      'pinned': true,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (senderRole == 'admin') {
      data['admin_unread_count'] = 0;
      data['teacher_unread_count'] = FieldValue.increment(1);
    } else if (senderRole == 'teacher') {
      data['teacher_unread_count'] = 0;
      data['teacher_last_read_at'] = FieldValue.serverTimestamp();
      data['admin_unread_count'] = FieldValue.increment(1);
    }

    return data;
  }

  static Map<String, dynamic> _keyPersonStudentThreadUpdateData({
    required String threadId,
    required String senderName,
    required String senderRole,
    required String lastMessage,
    String? studentName,
  }) {
    final data = <String, dynamic>{
      'thread_id': threadId,
      'is_keyperson_student': true,
      'last_message': lastMessage,
      'last_sender_name': senderName,
      'last_sender_role': senderRole,
      'last_message_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (senderRole == 'admin') {
      data['admin_unread_count'] = 0;
      data['admin_last_read_at'] = FieldValue.serverTimestamp();
      data['student_unread_count'] = FieldValue.increment(1);
    } else if (senderRole == 'student') {
      data['student_unread_count'] = 0;
      data['student_last_read_at'] = FieldValue.serverTimestamp();
      data['admin_unread_count'] = FieldValue.increment(1);
    }

    if (studentName != null && studentName.trim().isNotEmpty) {
      data['student_name'] = studentName.trim();
    }

    return data;
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

  static String _guessDocumentContentType(String fileName) {
    switch (_fileExtension(fileName)) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  static String _forwardPreview(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'text';
    final text = data['text']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;

    switch (type) {
      case 'image':
        return 'Forwarded photo';
      case 'video':
        return 'Forwarded video';
      case 'voice':
        return 'Forwarded voice message';
      case 'document':
        final fileName = data['file_name']?.toString().trim() ?? '';
        return fileName.isNotEmpty
            ? 'Forwarded $fileName'
            : 'Forwarded document';
      default:
        return 'Forwarded message';
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
      case 'admin':
        return 'admin';
      default:
        return null;
    }
  }
}

class AdminUnreadCounts {
  final int teacherUnread;
  final int studentUnread;

  AdminUnreadCounts({required this.teacherUnread, required this.studentUnread});
}
