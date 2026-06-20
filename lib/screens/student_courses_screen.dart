import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
import '../widgets/screen_header.dart';
import 'chat_screen.dart';

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
              (course) => StreamBuilder<int>(
                stream: FirestoreChatService.getStudentUnreadCount(
                  courseId: course.id,
                  threadId: session.lmsUser.lmsUserId,
                ),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;

                  return CourseCard(
                    course: course,
                    unreadCount: unreadCount,
                    unreadLabel: unreadCount == 1
                        ? '1 unread'
                        : '$unreadCount unread',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            title: course.name,
                            currentUserRole: 'student',
                            courseId: course.id,
                            threadId: session.lmsUser.lmsUserId,
                            senderName: session.appUser.name,
                            threadStudentName: session.appUser.name,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
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
