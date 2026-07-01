import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'chat_screen.dart';

class AdminChatsScreen extends StatelessWidget {
  final AuthSession session;

  const AdminChatsScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final items = _buildChatItems(session.courses);

    return AppScaffold(
      title: 'Chat Monitor',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Chat Monitor',
            subtitle: items.isEmpty
                ? 'No LMS chats available yet.'
                : '${items.length} conversation${items.length == 1 ? '' : 's'} ready from LMS sync.',
            icon: Icons.forum_rounded,
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const _EmptyState()
          else
            ...items.map((item) => _ChatTile(item: item, session: session)),
        ],
      ),
    );
  }

  List<_ChatItem> _buildChatItems(List<Course> courses) {
    final items = <_ChatItem>[];

    for (final course in courses) {
      items.add(
        _ChatItem(
          courseId: course.id,
          courseName: course.name,
          threadId: FirestoreChatService.adminTeacherThreadId,
          personName: course.teacherName?.trim().isNotEmpty == true
              ? course.teacherName!.trim()
              : 'Course Teacher',
          roleLabel: 'Teacher',
          subtitle: 'Direct admin-to-teacher chat',
          icon: Icons.menu_book_rounded,
          color: AppColors.teacher,
        ),
      );

      for (final student in course.students) {
        items.add(
          _ChatItem(
            courseId: course.id,
            courseName: course.name,
            threadId: student.id,
            personName: student.name,
            roleLabel: 'Student',
            subtitle:
                'Open this student thread from the LMS-synced course list.',
            icon: Icons.school_rounded,
            color: AppColors.student,
            studentName: student.name,
          ),
        );
      }
    }

    items.sort((a, b) {
      final courseCompare = a.courseName.toLowerCase().compareTo(
        b.courseName.toLowerCase(),
      );
      if (courseCompare != 0) return courseCompare;
      return a.personName.toLowerCase().compareTo(b.personName.toLowerCase());
    });

    return items;
  }
}

class _ChatItem {
  final String courseId;
  final String courseName;
  final String threadId;
  final String personName;
  final String roleLabel;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String? studentName;

  const _ChatItem({
    required this.courseId,
    required this.courseName,
    required this.threadId,
    required this.personName,
    required this.roleLabel,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.studentName,
  });
}

class _ChatTile extends StatelessWidget {
  final _ChatItem item;
  final AuthSession session;

  const _ChatTile({required this.item, required this.session});

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
          backgroundColor: item.color.withValues(alpha: 0.1),
          child: Icon(item.icon, color: item.color, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.personName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.roleLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: item.color,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '${item.subtitle} - ${item.courseName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              title: item.personName,
              currentUserRole: 'admin',
              courseId: item.courseId,
              threadId: item.threadId,
              senderName: session.appUser.name,
              threadStudentName: item.studentName,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(top: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 52, color: AppColors.muted),
            SizedBox(height: 14),
            Text(
              'No conversations yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Student chats will appear here once LMS courses are synced.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
