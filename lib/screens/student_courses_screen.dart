import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
import '../widgets/screen_header.dart';
import 'student_course_chats_screen.dart';

class StudentCoursesScreen extends StatelessWidget {
  final AuthSession session;

  const StudentCoursesScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'My Courses',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Hello, ${session.appUser.name}',
            subtitle: session.courses.isEmpty
                ? 'No open LMS courses are available for chat right now.'
                : 'Choose a course to chat with your teacher.',
            icon: Icons.school,
          ),
          const SizedBox(height: 18),
          if (session.courses.isEmpty)
            const _EmptyCoursesState()
          else
            ...session.courses.map(
              (course) => _StudentCourseCard(session: session, course: course),
            ),
        ],
      ),
    );
  }
}

class _StudentCourseCard extends StatefulWidget {
  final AuthSession session;
  final Course course;

  const _StudentCourseCard({required this.session, required this.course});

  @override
  State<_StudentCourseCard> createState() => _StudentCourseCardState();
}

class _StudentCourseCardState extends State<_StudentCourseCard> {
  int? _lastUnreadCount;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: FirestoreChatService.getStudentUnreadCount(
        courseId: widget.course.id,
        threadId: widget.session.lmsUser.lmsUserId,
      ),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        _showBannerWhenUnreadIncreases(unreadCount);

        return CourseCard(
          course: widget.course,
          unreadCount: unreadCount,
          unreadLabel: unreadCount == 1 ? '1 unread' : '$unreadCount unread',
          onTap: _openChat,
        );
      },
    );
  }

  void _showBannerWhenUnreadIncreases(int unreadCount) {
    final previous = _lastUnreadCount;
    _lastUnreadCount = unreadCount;

    if (previous == null || unreadCount <= previous) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      PushNotificationService.instance.showInAppNotification(
        title: widget.course.name,
        body: unreadCount == 1
            ? 'Your teacher sent a new message.'
            : '$unreadCount unread messages from your teacher.',
        onOpen: _openChat,
      );
    });
  }

  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentCourseChatsScreen(
          session: widget.session,
          course: widget.course,
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
