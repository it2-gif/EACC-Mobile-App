import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
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
        padding: const EdgeInsets.all(16),
        children: [
          ScreenHeader(
            title: 'Hello, ${session.appUser.name}',
            subtitle: session.courses.isEmpty
                ? 'No open LMS courses are assigned right now.'
                : 'Choose a course to view student chats.',
            icon: Icons.menu_book,
          ),
          const SizedBox(height: 20),
          if (session.courses.isEmpty)
            const _EmptyCoursesState()
          else
            ...session.courses.map(
              (course) => StreamBuilder<int>(
                stream: FirestoreChatService.getTeacherUnreadThreadCount(
                  courseId: course.id,
                ),
                builder: (context, snapshot) {
                  final unreadThreads = snapshot.data ?? 0;

                  return CourseCard(
                    course: course,
                    unreadCount: unreadThreads,
                    unreadLabel: unreadThreads == 1
                        ? '1 student'
                        : '$unreadThreads students',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TeacherThreadsScreen(
                            courseId: course.id,
                            courseName: course.name,
                            senderName: session.appUser.name,
                            students: course.students,
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
        padding: const EdgeInsets.all(20),
        child: Column(
          children: const [
            Icon(Icons.event_busy_outlined, size: 42, color: AppColors.muted),
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
