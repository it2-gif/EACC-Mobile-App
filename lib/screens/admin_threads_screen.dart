import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class AdminThreadsScreen extends StatelessWidget {
  final String courseId;
  final String courseName;
  final AuthSession session;
  final List<CourseStudent> students;

  const AdminThreadsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    required this.session,
    this.students = const [],
  });

  @override
  Widget build(BuildContext context) {
    final items = [...students]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(courseName, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'Admin view - Course $courseId',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: items.isEmpty
          ? const _FullState(
              icon: Icons.forum_outlined,
              title: 'No students found',
              subtitle:
                  'This course has no synced students yet, so there is no chat list to show.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final student = items[index];
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
                        student.name.isNotEmpty
                            ? student.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      student.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Open the conversation for this student.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          title: student.name,
                          currentUserRole: 'admin',
                          courseId: courseId,
                          threadId: student.id,
                          senderName: session.appUser.name,
                          threadStudentName: student.name,
                        ),
                      ),
                    ),
                  ),
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
