import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'chat_screen.dart';

class TeacherThreadsScreen extends StatelessWidget {
  static final NotificationApi _notificationApi = NotificationApi();

  final String courseId;
  final String courseName;
  final String viewerRole;
  final String senderName;
  final List<CourseStudent> students;

  const TeacherThreadsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.senderName,
    this.viewerRole = 'teacher',
    this.students = const [],
  });

  @override
  Widget build(BuildContext context) {
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
          ],
        ),
        actions: [
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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreChatService.getThreads(courseId: courseId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _FullState(
                    icon: Icons.error_outline,
                    title: 'Could not load student chats',
                    subtitle: '${snapshot.error}',
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final threads = snapshot.data?.docs ?? [];
                final items = _buildStudentChatItems(threads);

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _AnnouncementThreadCard(
                        courseId: courseId,
                        onTap: () => _openAnnouncementChat(context),
                      );
                    }

                    final item = items[index - 1];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                title: item.studentName,
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
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
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
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.studentName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15.5,
                                            ),
                                          ),
                                        ),
                                        if (item.unreadCount > 0)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              item.unreadCount > 99
                                                  ? '99+'
                                                  : '${item.unreadCount}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
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
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.border,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: AppColors.muted,
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
          threadId: FirestoreChatService.announcementThreadId,
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
                    threadId: student.id,
                    senderName: senderName,
                    senderRole: viewerRole,
                    text: text,
                    studentName: student.name,
                  );
                  await _notificationApi.notifyChatMessage(
                    courseId: courseId,
                    threadId: student.id,
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
    List<QueryDocumentSnapshot<Map<String, dynamic>>> threads,
  ) {
    final rosterById = {for (final student in students) student.id: student};
    final usedThreadIds = <String>{};
    final items = <_StudentChatItem>[];

    for (final doc in threads) {
      final data = doc.data();
      final threadId = doc.id;
      if (threadId == FirestoreChatService.announcementThreadId) continue;

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
          unreadCount: (data['teacher_unread_count'] as num?)?.toInt() ?? 0,
          lastMessageAt: lastMessageAt,
        ),
      );
      usedThreadIds.add(threadId);
    }

    for (final student in students) {
      if (usedThreadIds.contains(student.id)) continue;

      items.add(
        _StudentChatItem(
          threadId: student.id,
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
        final lastTime = formatThreadTime(
          data?['last_message_at'] ?? data?['updated_at'],
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.admin.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
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
                        const Row(
                          children: [
                            Expanded(
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
                            Icon(
                              Icons.push_pin_rounded,
                              size: 16,
                              color: AppColors.admin,
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
                      const Icon(Icons.chevron_right, color: AppColors.muted),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
