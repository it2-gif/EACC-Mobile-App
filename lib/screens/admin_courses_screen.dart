import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/auth_api.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
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
  Course? searchedCourse;
  bool isSearching = false;
  bool hasSearched = false;
  String? searchError;

  @override
  void dispose() {
    courseIdController.dispose();
    super.dispose();
  }

  Future<void> _searchCourse() async {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) return;

    setState(() {
      isSearching = true;
      hasSearched = true;
      searchError = null;
      searchedCourse = null;
    });

    try {
      final course = await AuthApi().fetchCourse(courseId);
      if (mounted) {
        setState(() {
          searchedCourse = course;
          isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          searchError = e.toString().replaceFirst('Exception: ', '');
          isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFullAccess = widget.session.appUser.isSuperAdmin;
    final courses = isFullAccess
        ? (searchedCourse != null ? [searchedCourse!] : <Course>[])
        : widget.session.courses;

    return AppScaffold(
      title: isFullAccess ? 'Admin Courses' : 'Linked Courses',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Hello, ${widget.session.appUser.name}',
            subtitle: isFullAccess
                ? 'Full access is enabled. Search a course ID to view its chats.'
                : widget.session.courses.isEmpty
                    ? 'No courses are linked to your contact-person account yet.'
                    : 'Contact-person access is active. You can monitor only your linked courses.',
            icon: isFullAccess
                ? Icons.admin_panel_settings_rounded
                : Icons.verified_user_outlined,
          ),
          const SizedBox(height: 18),
          if (isFullAccess) ...[
            _CourseLookupBar(
              controller: courseIdController,
              onSearch: _searchCourse,
              isSearching: isSearching,
            ),
            const SizedBox(height: 18),
          ],
          if (!isFullAccess || searchedCourse != null) ...[
            _AccessSummary(session: widget.session, courses: courses),
            const SizedBox(height: 18),
          ],
          if (isSearching)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (isFullAccess && !hasSearched)
            const _EmptyState(
              icon: Icons.search_rounded,
              title: 'Search for a course',
              subtitle: 'Enter a course ID above to view its details and chats.',
            )
          else if (isFullAccess && searchedCourse == null)
            _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Course not found',
              subtitle: searchError ?? 'No course with that ID exists in the database.',
            )
          else if (courses.isEmpty)
            _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: isFullAccess ? 'No active courses' : 'No linked courses',
              subtitle: isFullAccess
                  ? 'Courses will appear here after they are synced.'
                  : 'Ask a full-access admin to assign you as contact person in the LMS, then log in again.',
            )
          else
            ...courses.map((course) => _AdminCourseCard(
                  course: course,
                  session: widget.session,
                )),
        ],
      ),
    );
  }
}

class _CourseLookupBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final bool isSearching;

  const _CourseLookupBar({
    required this.controller,
    required this.onSearch,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Enter LMS Course ID (e.g. 2297)',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                keyboardType: TextInputType.number,
                onSubmitted: isSearching ? null : (_) => onSearch(),
              ),
            ),
            IconButton(
              onPressed: isSearching ? null : onSearch,
              icon: const Icon(Icons.search_rounded, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessSummary extends StatelessWidget {
  final AuthSession session;
  final List<Course> courses;

  const _AccessSummary({required this.session, required this.courses});

  @override
  Widget build(BuildContext context) {
    final isFullAccess = session.appUser.isSuperAdmin;
    final studentCount = courses.fold<int>(
      0,
      (total, course) => total + course.students.length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isFullAccess ? AppColors.admin : AppColors.primary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isFullAccess
                    ? Icons.workspace_premium_outlined
                    : Icons.link_outlined,
                color: isFullAccess ? AppColors.admin : AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isFullAccess
                        ? 'Full access admin'
                        : 'Contact manager courses and students',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}'
                    ' - $studentCount ${studentCount == 1 ? 'student' : 'students'}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminCourseCard extends StatefulWidget {
  final Course course;
  final AuthSession session;

  const _AdminCourseCard({required this.course, required this.session});

  @override
  State<_AdminCourseCard> createState() => _AdminCourseCardState();
}

class _AdminCourseCardState extends State<_AdminCourseCard> {
  int? _lastUnreadCount;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminUnreadCounts>(
      stream: FirestoreChatService.getAdminUnreadCounts(
        courseId: widget.course.id,
      ),
      builder: (context, snapshot) {
        final counts = snapshot.data;
        final teacherUnread = counts?.teacherUnread ?? 0;
        final studentUnread = counts?.studentUnread ?? 0;

        final totalUnread = teacherUnread + studentUnread;
        _notifyIfIncreased(totalUnread);

        final List<Widget> customBadges = [];
        if (teacherUnread > 0) {
          customBadges.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.teacher.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.teacher.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                teacherUnread == 1 ? '1 teacher' : '$teacherUnread teachers',
                style: const TextStyle(
                  color: AppColors.teacher,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        if (studentUnread > 0) {
          customBadges.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                studentUnread == 1 ? '1 student' : '$studentUnread students',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        return CourseCard(
          course: widget.course,
          customBadges: customBadges.isNotEmpty ? customBadges : null,
          onTap: _openThreads,
        );
      },
    );
  }

  void _notifyIfIncreased(int totalUnread) {
    final previous = _lastUnreadCount;
    _lastUnreadCount = totalUnread;
    if (previous == null || totalUnread <= previous) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PushNotificationService.instance.showInAppNotification(
        title: widget.course.name,
        body: 'You have new unread messages in this course.',
        onOpen: _openThreads,
      );
    });
  }

  void _openThreads() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminThreadsScreen(
          courseId: widget.course.id,
          courseName: widget.course.name,
          teacherName: widget.course.teacherName,
          students: widget.course.students,
          session: widget.session,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Icon(icon, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
