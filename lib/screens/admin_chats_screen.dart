import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'chat_screen.dart';

class AdminChatsScreen extends StatefulWidget {
  final AuthSession session;

  const AdminChatsScreen({super.key, required this.session});

  @override
  State<AdminChatsScreen> createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  final courseIdController = TextEditingController();
  Course? loadedCourse;
  bool searched = false;

  @override
  void dispose() {
    courseIdController.dispose();
    super.dispose();
  }

  void _loadCourse() {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) return;

    Course? match;
    for (final course in widget.session.courses) {
      if (course.id == courseId) {
        match = course;
        break;
      }
    }

    setState(() {
      searched = true;
      loadedCourse = match;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = loadedCourse == null ? <_ChatItem>[] : _buildChatItems();

    return AppScaffold(
      title: 'Chat Monitor',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Chat Monitor',
            subtitle:
                'Load one LMS course to monitor its teacher and student conversations.',
            icon: Icons.forum_rounded,
          ),
          const SizedBox(height: 18),
          _CourseLookupBar(controller: courseIdController, onLoad: _loadCourse),
          const SizedBox(height: 18),
          if (!searched)
            const _EmptyState(
              icon: Icons.filter_alt_rounded,
              title: 'Choose a course',
              subtitle: 'Enter a course ID to show its monitorable chats.',
            )
          else if (loadedCourse == null)
            const _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Course not found',
              subtitle:
                  'This admin session does not include that course. Log in again after LMS sync if it was recently added.',
            )
          else if (items.isEmpty)
            const _EmptyState(
              icon: Icons.forum_outlined,
              title: 'No conversations yet',
              subtitle: 'This course has no LMS student chats available.',
            )
          else
            ...items.map(
              (item) => _ChatTile(item: item, session: widget.session),
            ),
        ],
      ),
    );
  }

  List<_ChatItem> _buildChatItems() {
    final items = <_ChatItem>[];
    final course = loadedCourse;
    if (course == null) return items;

    items
      ..add(
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
      )
      ..addAll(
        course.students.map(
          (student) => _ChatItem(
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
        ),
      );

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

class _CourseLookupBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onLoad;

  const _CourseLookupBar({required this.controller, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Course ID',
                  hintText: 'Enter course ID',
                  prefixIcon: Icon(Icons.filter_alt_rounded),
                ),
                onSubmitted: (_) => onLoad(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: onLoad,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Load'),
            ),
          ],
        ),
      ),
    );
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
              isSuperAdmin: session.appUser.isSuperAdmin,
              canManageAllMessages: session.appUser.canViewAllCourses,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: AppColors.muted),
            const SizedBox(height: 14),
            Text(
              title,
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
