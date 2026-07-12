import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import 'chat_screen.dart';

class AdminThreadsScreen extends StatelessWidget {
  final String courseId;
  final String courseName;
  final String? teacherName;
  final AuthSession session;
  final List<CourseStudent> students;

  const AdminThreadsScreen({
    super.key,
    required this.courseId,
    required this.courseName,
    this.teacherName,
    required this.session,
    this.students = const [],
  });

  @override
  Widget build(BuildContext context) {
    final items = [...students]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final displayTeacher = teacherName?.trim();
    final teacherTitle = displayTeacher != null && displayTeacher.isNotEmpty
        ? '$displayTeacher chat'
        : 'Teacher chat';

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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _AdminThreadTile(
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
                        isSuperAdmin: session.appUser.isSuperAdmin,
                        canManageAllMessages: session.appUser.canViewAllCourses,
                      ),
                    ),
                  ),
                ),

                _AdminThreadTile(
                  title: teacherTitle,
                  subtitle:
                      'Private chat between the teacher and contact person.',
                  icon: Icons.admin_panel_settings_rounded,
                  color: AppColors.teacher,
                  badge: const Icon(
                    Icons.push_pin_rounded,
                    size: 16,
                    color: AppColors.teacher,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        title: teacherTitle,
                        currentUserRole: 'admin',
                        courseId: courseId,
                        threadId: FirestoreChatService.adminTeacherThreadId,
                        senderName: session.appUser.name,
                        isSuperAdmin: session.appUser.isSuperAdmin,
                        canManageAllMessages: session.appUser.canViewAllCourses,
                      ),
                    ),
                  ),
                ),

                if (items.isNotEmpty) const _AdminThreadSection('Students'),
                for (final student in items) ...[
                  _AdminThreadTile(
                    title: '${student.name} - teacher chat',
                    subtitle: 'View the student conversation with the teacher.',
                    iconLabel: student.name.isNotEmpty
                        ? student.name[0].toUpperCase()
                        : '?',
                    color: AppColors.primary,
                    badge: _ThreadBadge(
                      label: 'TEACHER',
                      color: AppColors.primary,
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
                          isSuperAdmin: session.appUser.isSuperAdmin,
                          canManageAllMessages:
                              session.appUser.canViewAllCourses,
                        ),
                      ),
                    ),
                  ),
                  _AdminThreadTile(
                    title: '${student.name} - contact person chat',
                    subtitle: 'Private chat between you and this student.',
                    icon: Icons.verified_user_rounded,
                    color: AppColors.admin,
                    badge: _ThreadBadge(
                      label: 'CONTACT PERSON',
                      color: AppColors.admin,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          title: '${student.name} - contact person',
                          currentUserRole: 'admin',
                          courseId: courseId,
                          threadId:
                              FirestoreChatService.keyPersonStudentThreadId(
                                student.id,
                              ),
                          senderName: session.appUser.name,
                          threadStudentName: student.name,
                          isSuperAdmin: session.appUser.isSuperAdmin,
                          canManageAllMessages:
                              session.appUser.canViewAllCourses,
                        ),
                      ),
                    ),
                  ),
                ],
                if (items.isEmpty) const _AdminEmptyStudentsState(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminThreadSection extends StatelessWidget {
  final String title;

  const _AdminThreadSection(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ThreadBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _ThreadBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AdminEmptyStudentsState extends StatelessWidget {
  const _AdminEmptyStudentsState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          'No students are linked to this course yet.',
          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: icon == null
              ? Text(
                  iconLabel ?? '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
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
