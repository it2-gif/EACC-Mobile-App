import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'chat_screen.dart';

class AdminThreadsScreen extends StatelessWidget {
  final String courseId;
  final String courseName;
  final AuthSession session;

  const AdminThreadsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.session,
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
              'Admin view • Course $courseId',
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
              title: 'Could not load threads',
              subtitle: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _FullState(
              icon: Icons.chat_bubble_outline,
              title: 'No threads yet',
              subtitle: 'No students have started a chat in this course.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final threadId = docs[index].id;
              final studentName = data['student_name'] as String? ?? threadId;
              final lastMessage = data['last_message'] as String? ?? '';
              final lastSenderName = data['last_sender_name'] as String? ?? '';
              final lastSenderRole = data['last_sender_role'] as String? ?? '';
              final updatedAt = (data['updated_at'] as Timestamp?)?.toDate();
              final timeLabel = updatedAt != null
                  ? formatThreadTime(updatedAt)
                  : '';

              final roleColor = lastSenderRole == 'teacher'
                  ? AppColors.teacher
                  : lastSenderRole == 'admin'
                      ? AppColors.admin
                      : AppColors.student;

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                    child: Text(
                      studentName.isNotEmpty
                          ? studentName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(
                    studentName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: lastMessage.isEmpty
                      ? const Text(
                          'No messages yet',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.muted,
                            ),
                            children: [
                              TextSpan(
                                text: '$lastSenderName: ',
                                style: TextStyle(
                                  color: roleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: lastMessage),
                            ],
                          ),
                        ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        timeLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.admin.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'ADMIN',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.admin,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        title: studentName,
                        currentUserRole: 'admin',
                        courseId: courseId,
                        threadId: threadId,
                        senderName: session.appUser.name,
                        threadStudentName: studentName,
                      ),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
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
