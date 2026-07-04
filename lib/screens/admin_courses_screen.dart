import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'admin_threads_screen.dart';

class AdminCoursesScreen extends StatefulWidget {
  final AuthSession session;

  const AdminCoursesScreen({super.key, required this.session});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
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
    return AppScaffold(
      title: 'All Courses',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Course lookup',
            subtitle:
                'Enter a course ID to open its students and chats without rendering every LMS course.',
            icon: Icons.menu_book_rounded,
          ),
          const SizedBox(height: 18),
          _CourseLookupBar(controller: courseIdController, onLoad: _loadCourse),
          const SizedBox(height: 18),
          if (!searched)
            const _FullState(
              icon: Icons.filter_alt_rounded,
              title: 'Choose a course',
              subtitle: 'Use the LMS course ID, for example 2203 or 2285.',
            )
          else if (loadedCourse == null)
            const _FullState(
              icon: Icons.search_off_rounded,
              title: 'Course not found',
              subtitle:
                  'This admin session does not include that course. Log in again after LMS sync if it was recently added.',
            )
          else
            _CourseCard(course: loadedCourse!, session: widget.session),
        ],
      ),
    );
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

class _CourseCard extends StatelessWidget {
  final Course course;
  final AuthSession session;

  const _CourseCard({required this.course, required this.session});

  @override
  Widget build(BuildContext context) {
    final studentCount = course.students.length;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: AppColors.primary,
            size: 22,
          ),
        ),
        title: Text(
          course.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'ID: ${course.id} - $studentCount student${studentCount == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminThreadsScreen(
              courseId: course.id,
              courseName: course.name,
              teacherName: course.teacherName,
              students: course.students,
              session: session,
            ),
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
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
