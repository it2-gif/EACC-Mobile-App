import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'admin_threads_screen.dart';

class AdminCoursesScreen extends StatelessWidget {
  final AuthSession session;

  const AdminCoursesScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'All Courses',
      showLogout: false,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('courses')
            .orderBy(FieldPath.documentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _FullState(
              icon: Icons.error_outline,
              title: 'Could not load courses',
              subtitle: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              ScreenHeader(
                title: 'All Courses',
                subtitle: docs.isEmpty
                    ? 'No courses found in Firestore yet.'
                    : '${docs.length} course${docs.length == 1 ? '' : 's'} — tap to view student threads.',
                icon: Icons.menu_book_rounded,
              ),
              const SizedBox(height: 18),
              if (docs.isEmpty)
                const _FullState(
                  icon: Icons.menu_book_outlined,
                  title: 'No courses yet',
                  subtitle:
                      'Courses will appear here once students start chatting.',
                )
              else
                ...docs.map((doc) {
                  final courseId = doc.id;
                  final data = doc.data();
                  final courseName = data['name'] as String? ??
                      data['course_name'] as String? ??
                      courseId;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CourseCard(
                      courseId: courseId,
                      courseName: courseName,
                      session: session,
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final String courseId;
  final String courseName;
  final AuthSession session;

  const _CourseCard({
    required this.courseId,
    required this.courseName,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('courses')
          .doc(courseId)
          .collection('threads')
          .snapshots(),
      builder: (context, threadSnap) {
        final threadCount = threadSnap.data?.docs.length ?? 0;

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
              courseName,
              style: const TextStyle(fontWeight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'ID: $courseId  •  $threadCount thread${threadCount == 1 ? '' : 's'}',
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
                  courseId: courseId,
                  courseName: courseName,
                  session: session,
                ),
              ),
            ),
          ),
        );
      },
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
