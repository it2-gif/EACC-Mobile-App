import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
import '../widgets/screen_header.dart';
import 'teacher_threads_screen.dart';

class TeacherCoursesScreen extends StatelessWidget {
  final AuthSession session;

  const TeacherCoursesScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Teacher Courses',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Hello, ${session.appUser.name}',
            subtitle: session.courses.isEmpty
                ? 'No open LMS courses are assigned right now.'
                : 'Choose a course to view student chats.',
            icon: Icons.menu_book,
          ),
          const SizedBox(height: 18),
          if (session.courses.isEmpty)
            const _EmptyCoursesState()
          else
            ...session.courses.map(
              (course) => _TeacherCourseCard(session: session, course: course),
            ),
        ],
      ),
    );
  }
}

class _TeacherCourseCard extends StatefulWidget {
  final AuthSession session;
  final Course course;

  const _TeacherCourseCard({required this.session, required this.course});

  @override
  State<_TeacherCourseCard> createState() => _TeacherCourseCardState();
}

class _TeacherCourseCardState extends State<_TeacherCourseCard> {
  int? _lastUnreadThreads;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreChatService.getTeacherUnreadThreadCount(
        courseId: widget.course.id,
      ),
      builder: (context, snapshot) {
        final unreadThreads = snapshot.data ?? 0;
        _showBannerWhenUnreadIncreases(unreadThreads);

        return CourseCard(
          course: widget.course,
          unreadCount: unreadThreads,
          unreadLabel: unreadThreads == 1
              ? '1 student'
              : '$unreadThreads students',
          onTap: _openThreads,
        );
      },
    );
  }

  void _showBannerWhenUnreadIncreases(int unreadThreads) {
    final previous = _lastUnreadThreads;
    _lastUnreadThreads = unreadThreads;

    if (previous == null || unreadThreads <= previous) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      PushNotificationService.instance.showInAppNotification(
        title: widget.course.name,
        body: unreadThreads == 1
            ? 'A student sent a new message.'
            : '$unreadThreads students have unread messages.',
        onOpen: _openThreads,
      );
    });
  }

  void _openThreads() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherThreadsScreen(
          courseId: widget.course.id,
          courseName: widget.course.name,
          senderName: widget.session.appUser.name,
          students: widget.course.students,
        ),
      ),
    );
  }
}

class _EmptyCoursesState extends StatelessWidget {
  const _EmptyCoursesState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: const [
            Icon(Icons.event_busy_outlined, size: 44, color: AppColors.muted),
            SizedBox(height: 12),
            Text(
              'No open courses',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 6),
            Text(
              'Only courses currently open in the LMS will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
