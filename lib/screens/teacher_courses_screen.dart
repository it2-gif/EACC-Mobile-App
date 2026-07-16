import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/screen_header.dart';
import '../widgets/support_entry_card.dart';
import 'teacher_threads_screen.dart';

class TeacherCoursesScreen extends StatelessWidget {
  final AuthSession session;

  const TeacherCoursesScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Teacher Courses',
      floatingActionButton: SupportHelpButton(session: session),
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
      stream: FirestoreChatService.getTeacherUnreadMessageCount(
        courseId: widget.course.id,
        studentThreadIds: widget.course.students.map((student) => student.id),
      ),
      builder: (context, snapshot) {
        final unreadMessages = snapshot.data ?? 0;
        _showBannerWhenUnreadIncreases(unreadMessages);

        return CourseCard(
          course: widget.course,
          unreadCount: unreadMessages,
          onTap: _openThreads,
        );
      },
    );
  }

  void _showBannerWhenUnreadIncreases(int unreadMessages) {
    final previous = _lastUnreadThreads;
    _lastUnreadThreads = unreadMessages;

    if (previous == null || unreadMessages <= previous) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      PushNotificationService.instance.showInAppNotification(
        title: widget.course.displayTitle,
        body: unreadMessages == 1
            ? 'A student sent a new message.'
            : '$unreadMessages unread messages from students.',
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
          courseName: widget.course.displayTitle,
          senderName: widget.session.appUser.name,
          students: widget.course.students,
          viewerLmsUserId: widget.session.lmsUser.lmsUserId,
          isSuperAdmin: widget.session.appUser.isSuperAdmin,
          courseKeyPersonLmsUserId: widget.course.keyPersonLmsUserId,
          courseKeyPersonName: widget.course.keyPersonName,
        ),
      ),
    );
  }
}

class _EmptyCoursesState extends StatelessWidget {
  const _EmptyCoursesState();

  @override
  Widget build(BuildContext context) {
    return const PolishedStateCard(
      icon: Icons.event_busy_outlined,
      title: 'No open courses',
      message: 'Only courses currently open in the LMS will appear here.',
      color: AppColors.teacher,
    );
  }
}
