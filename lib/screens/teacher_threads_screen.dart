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
    this.viewerRole = 'teacher',
    this.senderName = 'Mohamed El-Sayad',
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
              subtitle: 'No enrolled students were found for this course.',
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
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.12,
                          ),
                          child: Text(
                            item.studentName.isNotEmpty
                                ? item.studentName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.studentName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
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
                            if (item.unreadCount > 0)
                              Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(999),
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
                            if (item.lastTime.isNotEmpty)
                              Text(
                                item.lastTime,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const SizedBox(height: 2),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AppColors.muted,
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
    );
  }

  List<_StudentChatItem> _buildStudentChatItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> threads,
  ) {
    final rosterById = {
      for (final student in students) student.id: student,
    };
    final usedThreadIds = <String>{};
    final items = <_StudentChatItem>[];

    for (final doc in threads) {
      final data = doc.data();
      final threadId = doc.id;
      final rosterStudent = rosterById[threadId];
      final studentName =
          rosterStudent?.name ?? data['student_name']?.toString() ?? 'Student';
      final lastTime = formatThreadTime(
        data['last_message_at'] ?? data['updated_at'],
      );

      items.add(
        _StudentChatItem(
          threadId: threadId,
          studentName: studentName,
          lastMessage: data['last_message']?.toString() ?? 'No messages yet',
          lastTime: lastTime,
          unreadCount: (data['teacher_unread_count'] as num?)?.toInt() ?? 0,
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
        ),
      );
    }

    return items;
  }
}

class _StudentChatItem {
  final String threadId;
  final String studentName;
  final String lastMessage;
  final String lastTime;
  final int unreadCount;

  const _StudentChatItem({
    required this.threadId,
    required this.studentName,
    required this.lastMessage,
    required this.lastTime,
    required this.unreadCount,
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
