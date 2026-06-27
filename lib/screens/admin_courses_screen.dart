import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'admin_threads_screen.dart';

class AdminCoursesScreen extends StatelessWidget {
  final AuthSession session;

  const AdminCoursesScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final courses = [...session.courses]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return AppScaffold(
      title: 'All Courses',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'All Courses',
            subtitle: courses.isEmpty
                ? 'No LMS courses were synced for this admin account yet.'
                : '${courses.length} course${courses.length == 1 ? '' : 's'} synced from the LMS.',
            icon: Icons.menu_book_rounded,
          ),
          const SizedBox(height: 18),
          if (courses.isEmpty)
            const _FullState(
              icon: Icons.menu_book_outlined,
              title: 'No courses yet',
              subtitle:
                  'Courses will appear here after LMS sync brings them into Postgres.',
            )
          else
            ...courses.map((course) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CourseCard(course: course, session: session),
              );
            }),
        ],
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
