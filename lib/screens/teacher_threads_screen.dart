import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'chat_screen.dart';

class TeacherThreadsScreen extends StatelessWidget {
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

                if (items.isEmpty) {
                  return const _FullState(
                    icon: Icons.forum_outlined,
                    title: 'No students found',
                    subtitle:
                        'No enrolled students were found for this course.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];

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

  List<_StudentChatItem> _buildStudentChatItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> threads,
  ) {
    final rosterById = {for (final student in students) student.id: student};
    final usedThreadIds = <String>{};
    final items = <_StudentChatItem>[];

    for (final doc in threads) {
      final data = doc.data();
      final threadId = doc.id;
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
