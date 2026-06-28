import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
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
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _AdminThreadTile(
                    title: 'Announcement chat',
                    subtitle: 'Pinned course-wide announcement thread.',
                    icon: Icons.campaign_rounded,
                    color: AppColors.admin,
                    badge: const Icon(
                      Icons.push_pin_rounded,
                      size: 16,
                      color: AppColors.admin,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          title: 'Announcement chat',
                          currentUserRole: 'admin',
                          courseId: courseId,
                          threadId: FirestoreChatService.announcementThreadId,
                          senderName: session.appUser.name,
                        ),
                      ),
                    ),
                  );
                }

                final student = items[index - 1];
                return _AdminThreadTile(
                  title: student.name,
                  subtitle: 'Open the conversation for this student.',
                  iconLabel: student.name.isNotEmpty
                      ? student.name[0].toUpperCase()
                      : '?',
                  color: AppColors.primary,
                  badge: Container(
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminThreadTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final String? iconLabel;
  final Widget? badge;

  const _AdminThreadTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.icon,
    this.iconLabel,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: icon == null
              ? Text(
                  iconLabel ?? '?',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : Icon(icon, color: color),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ?badge,
          ],
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
        ),
        onTap: onTap,
      ),
    );
  }
}
