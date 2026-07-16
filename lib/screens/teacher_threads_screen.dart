import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/chat_thread_resolver.dart';
import '../services/firestore_chat_service.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/unread_badge.dart';
import 'chat_screen.dart';

class TeacherThreadsScreen extends StatelessWidget {
  static final NotificationApi _notificationApi = NotificationApi();

  final String courseId;
  final String courseName;
  final String viewerRole;
  final String senderName;
  final List<CourseStudent> students;
  final String viewerLmsUserId;
  final bool isSuperAdmin;
  final String? courseKeyPersonLmsUserId;
  final String? courseKeyPersonName;

  const TeacherThreadsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.senderName,
    required this.viewerLmsUserId,
    required this.isSuperAdmin,
    this.courseKeyPersonLmsUserId,
    this.courseKeyPersonName,
    this.viewerRole = 'teacher',
    this.students = const [],
  });

  @override
  Widget build(BuildContext context) {
    final canManageCourse =
        isSuperAdmin ||
        (courseKeyPersonLmsUserId != null &&
            viewerLmsUserId == courseKeyPersonLmsUserId);
    final keyPersonName = courseKeyPersonName?.trim();
    final keyPersonDisplayName =
        keyPersonName != null && keyPersonName.isNotEmpty
        ? keyPersonName
        : 'Contact person';
    final hasKeyPersonChat =
        (keyPersonName != null && keyPersonName.isNotEmpty) ||
        (courseKeyPersonLmsUserId?.trim().isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(courseName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'Course $courseId',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.normal,
              ),
            ),
            if (keyPersonName != null && keyPersonName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Contact person: $keyPersonName',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (canManageCourse)
            IconButton(
              tooltip: 'Broadcast message',
              icon: const Icon(Icons.mark_email_unread_rounded),
              onPressed: students.isEmpty
                  ? null
                  : () => _showStudentBroadcastSheet(context),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: StreamBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
              stream: FirestoreChatService.getThreadDocuments(
                courseId: courseId,
                threadIds: students.map(
                  (student) =>
                      ChatThreadResolver.studentTeacherThreadId(student.id),
                ),
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _FullState(
                    icon: Icons.error_outline,
                    title: 'Could not load student chats',
                    subtitle: '${snapshot.error}',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: PolishedLoadingCard(
                      title: 'Loading course chats',
                      message:
                          'Preparing announcements, contact chat, and student threads.',
                    ),
                  );
                }

                final threads =
                    snapshot.data ?? <DocumentSnapshot<Map<String, dynamic>>>[];
                final items = _buildStudentChatItems(threads);
                final threadItemCount =
                    items.length + 1 + (hasKeyPersonChat ? 1 : 0);
                final totalItems = threadItemCount + 2;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: totalItems,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _TeacherCourseHeader(
                        courseName: courseName,
                        courseId: courseId,
                        studentCount: students.length,
                        keyPersonName: keyPersonName,
                        canManageCourse: canManageCourse,
                        viewerRole: viewerRole,
                      );
                    }

                    if (index == 1) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(2, 8, 2, 12),
                        child: _SectionLabel(
                          title: 'Course conversations',
                          subtitle:
                              'Announcements, contact-person chat, and student threads',
                        ),
                      );
                    }

                    final contentIndex = index - 2;

                    if (contentIndex == 0) {
                      return _AnnouncementThreadCard(
                        courseId: courseId,
                        onTap: () => _openAnnouncementChat(context),
                      );
                    }

                    if (hasKeyPersonChat && contentIndex == 1) {
                      return _AdminTeacherThreadCard(
                        courseId: courseId,
                        title: 'Contact person: $keyPersonDisplayName',
                        subtitle: 'Talk directly with $keyPersonDisplayName',
                        onTap: () =>
                            _openAdminChat(context, keyPersonDisplayName),
                      );
                    }

                    final itemIndex = hasKeyPersonChat
                        ? contentIndex - 2
                        : contentIndex - 1;
                    final item = items[itemIndex];
                    final compact = MediaQuery.sizeOf(context).width < 390;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                title: 'Student: ${item.studentName}',
                                currentUserRole: viewerRole,
                                courseId: courseId,
                                threadId: item.threadId,
                                senderName: senderName,
                                threadStudentName: item.studentName,
                              ),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!compact) ...[
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        AppColors.student.withValues(
                                          alpha: 0.16,
                                        ),
                                        AppColors.student.withValues(
                                          alpha: 0.06,
                                        ),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.student.withValues(
                                        alpha: 0.14,
                                      ),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    item.studentName.isNotEmpty
                                        ? item.studentName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: AppColors.student,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Student: ${item.studentName}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ),
                                        if (item.unreadCount > 0) ...[
                                          const SizedBox(width: 8),
                                          UnreadBadge(
                                            count: item.unreadCount,
                                            compact: true,
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      item.lastMessage,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item.lastTime.isNotEmpty)
                                    Text(
                                      item.lastTime,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  if (!compact) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: AppColors.border,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 19,
                                        color: AppColors.primaryDark,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
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

  void _openAnnouncementChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: 'Announcement chat',
          currentUserRole: viewerRole,
          courseId: courseId,
          threadId: ChatThreadResolver.announcementThreadId,
          senderName: senderName,
        ),
      ),
    );
  }

  void _openAdminChat(BuildContext context, String keyPersonDisplayName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: 'Contact person: $keyPersonDisplayName',
          currentUserRole: viewerRole,
          courseId: courseId,
          threadId: ChatThreadResolver.adminTeacherThreadId,
          senderName: senderName,
        ),
      ),
    );
  }

  Future<void> _showStudentBroadcastSheet(BuildContext context) async {
    final selectedIds = students.map((student) => student.id).toSet();
    final messageController = TextEditingController();
    var isSending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> sendBroadcast() async {
              final text = messageController.text.trim();
              if (text.isEmpty || selectedIds.isEmpty || isSending) return;

              setSheetState(() => isSending = true);
              try {
                final selectedStudents = students.where(
                  (student) => selectedIds.contains(student.id),
                );
                for (final student in selectedStudents) {
                  final messageId = await FirestoreChatService.sendTextMessage(
                    courseId: courseId,
                    threadId: ChatThreadResolver.studentTeacherThreadId(
                      student.id,
                    ),
                    senderName: senderName,
                    senderRole: viewerRole,
                    text: text,
                    studentName: student.name,
                  );
                  await _notificationApi.notifyChatMessage(
                    courseId: courseId,
                    threadId: ChatThreadResolver.studentTeacherThreadId(
                      student.id,
                    ),
                    senderRole: viewerRole,
                    senderName: senderName,
                    messageType: 'text',
                    messageId: messageId,
                    previewText: text,
                    studentName: student.name,
                  );
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Message sent to ${selectedIds.length} student${selectedIds.length == 1 ? '' : 's'}.',
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Broadcast failed: $error')),
                  );
                }
              } finally {
                if (context.mounted) {
                  setSheetState(() => isSending = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.border,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Send to selected students',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'The same message will be delivered in each private chat.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: messageController,
                        minLines: 3,
                        maxLines: 5,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Write the message',
                          prefixIcon: Icon(Icons.edit_note_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => setSheetState(() {
                              selectedIds
                                ..clear()
                                ..addAll(students.map((student) => student.id));
                            }),
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            onPressed: () => setSheetState(selectedIds.clear),
                            child: const Text('Clear'),
                          ),
                          const Spacer(),
                          Text(
                            '${selectedIds.length}/${students.length}',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            final student = students[index];
                            final selected = selectedIds.contains(student.id);
                            return _StudentSelectionTile(
                              name: student.name,
                              subtitle: 'Student ${student.id}',
                              selected: selected,
                              onTap: () {
                                setSheetState(() {
                                  if (selected) {
                                    selectedIds.remove(student.id);
                                  } else {
                                    selectedIds.add(student.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isSending ? null : sendBroadcast,
                          icon: isSending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: const Text('Send message'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    messageController.dispose();
  }

  List<_StudentChatItem> _buildStudentChatItems(
    List<DocumentSnapshot<Map<String, dynamic>>> threads,
  ) {
    final rosterById = {for (final student in students) student.id: student};
    final usedThreadIds = <String>{};
    final items = <_StudentChatItem>[];

    for (final doc in threads) {
      final data = doc.data();
      if (data == null) continue;

      final threadId = doc.id;
      if (threadId == ChatThreadResolver.announcementThreadId) continue;
      if (threadId == ChatThreadResolver.adminTeacherThreadId) continue;
      if (ChatThreadResolver.isStudentContactPersonThreadId(threadId)) {
        continue;
      }

      final rosterStudent = rosterById[threadId];
      final studentName =
          rosterStudent?.name ?? data['student_name']?.toString() ?? 'Student';
      final lastMessageAt = _readTimestamp(
        data['last_message_at'] ?? data['updated_at'],
      );

      items.add(
        _StudentChatItem(
          threadId: threadId,
          studentName: studentName,
          lastMessage: data['last_message']?.toString() ?? 'No messages yet',
          lastTime: formatThreadTime(lastMessageAt),
          unreadCount: FirestoreChatService.readTeacherUnreadCount(data),
          lastMessageAt: lastMessageAt,
        ),
      );
      usedThreadIds.add(threadId);
    }

    for (final student in students) {
      if (usedThreadIds.contains(student.id)) continue;

      items.add(
        _StudentChatItem(
          threadId: ChatThreadResolver.studentTeacherThreadId(student.id),
          studentName: student.name,
          lastMessage: 'No messages yet',
          lastTime: '',
          unreadCount: 0,
          lastMessageAt: null,
        ),
      );
    }

    items.sort((a, b) {
      final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return items;
  }

  DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class _TeacherCourseHeader extends StatelessWidget {
  final String courseName;
  final String courseId;
  final int studentCount;
  final String? keyPersonName;
  final bool canManageCourse;
  final String viewerRole;

  const _TeacherCourseHeader({
    required this.courseName,
    required this.courseId,
    required this.studentCount,
    required this.keyPersonName,
    required this.canManageCourse,
    required this.viewerRole,
  });

  @override
  Widget build(BuildContext context) {
    final contactName = keyPersonName?.trim();
    final isContactManager = viewerRole == 'admin' || canManageCourse;

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
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courseName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(label: 'Course $courseId'),
                    _HeroChip(
                      label:
                          '$studentCount ${studentCount == 1 ? 'student' : 'students'}',
                    ),
                    _HeroChip(
                      label: isContactManager
                          ? 'Contact manager view'
                          : 'Teacher view',
                    ),
                    if (contactName != null && contactName.isNotEmpty)
                      _HeroChip(label: 'Contact person: $contactName'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;

  const _HeroChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.chat_bubble_rounded,
            color: AppColors.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentChatItem {
  final String threadId;
  final String studentName;
  final String lastMessage;
  final String lastTime;
  final int unreadCount;
  final DateTime? lastMessageAt;

  const _StudentChatItem({
    required this.threadId,
    required this.studentName,
    required this.lastMessage,
    required this.lastTime,
    required this.unreadCount,
    required this.lastMessageAt,
  });
}

class _AnnouncementThreadCard extends StatelessWidget {
  final String courseId;
  final VoidCallback onTap;

  const _AnnouncementThreadCard({required this.courseId, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreChatService.getAnnouncementThread(courseId: courseId),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final lastMessage =
            data?['last_message']?.toString() ?? 'Post a course announcement';
        final reads = data?['announcement_reads'];
        final readCount = FirestoreChatService.announcementStudentReadCount(
          reads,
        );
        final pinned = data?['pinned'] != false;
        final lastTime = formatThreadTime(
          data?['last_message_at'] ?? data?['updated_at'],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.admin.withValues(alpha: 0.16),
                          AppColors.admin.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.admin.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.campaign_rounded,
                      color: AppColors.admin,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Announcement chat',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: pinned
                                  ? 'Unpin announcement'
                                  : 'Pin announcement',
                              icon: Icon(
                                pinned
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: pinned
                                    ? AppColors.admin
                                    : AppColors.muted,
                              ),
                              onSelected: (_) async {
                                await FirestoreChatService.setAnnouncementPinned(
                                  courseId: courseId,
                                  pinned: !pinned,
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      pinned
                                          ? 'Announcement chat unpinned.'
                                          : 'Announcement chat pinned.',
                                    ),
                                  ),
                                );
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: pinned ? 'unpin' : 'pin',
                                  child: Row(
                                    children: [
                                      Icon(
                                        pinned
                                            ? Icons.push_pin_outlined
                                            : Icons.push_pin_rounded,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        pinned
                                            ? 'Unpin announcement'
                                            : 'Pin announcement',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          lastMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$readCount read',
                          style: const TextStyle(
                            color: AppColors.admin,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastTime.isNotEmpty)
                        Text(
                          lastTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 8),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminTeacherThreadCard extends StatelessWidget {
  final String courseId;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminTeacherThreadCard({
    required this.courseId,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreChatService.getThread(
        courseId: courseId,
        threadId: ChatThreadResolver.adminTeacherThreadId,
      ),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final unread = FirestoreChatService.readTeacherUnreadCount(data);
        final lastMessage = data?['last_message']?.toString() ?? subtitle;
        final lastTime = formatThreadTime(
          data?['last_message_at'] ?? data?['updated_at'],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.teacher.withValues(alpha: 0.16),
                          AppColors.teacher.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.teacher.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.teacher,
                    ),
                  ),
                  const SizedBox(width: 14),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15.5,
                                ),
                              ),
                            ),
                            UnreadBadge(count: unread, compact: true),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          lastMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (lastTime.isNotEmpty)
                        Text(
                          lastTime,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 8),
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StudentSelectionTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StudentSelectionTile({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary
                        : AppColors.student.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.student,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FullState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FullState({
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
        color: AppColors.warning,
      ),
    );
  }
}
