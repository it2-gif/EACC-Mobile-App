import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/chat_thread_resolver.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
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
      title: 'Course Chats',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Course Chats',
            subtitle:
                'Search one LMS course to open announcements, teacher chats, and student chats.',
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
          courseName: course.displayName,
          threadId: ChatThreadResolver.adminTeacherThreadId,
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
            courseName: course.displayName,
            threadId: ChatThreadResolver.studentTeacherThreadId(student.id),
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
    final compact = MediaQuery.sizeOf(context).width < 520;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Flex(
          direction: compact ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Course ID',
                  hintText: 'Enter LMS Course ID, for example 2203',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onSubmitted: (_) => onLoad(),
              )
            else
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    labelText: 'Course ID',
                    hintText: 'Enter LMS Course ID, for example 2203',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => onLoad(),
                ),
              ),
            SizedBox(width: compact ? 0 : 10, height: compact ? 10 : 0),
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
    final displayTitle = '${item.roleLabel}: ${item.personName}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              title: displayTitle,
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
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      item.color.withValues(alpha: 0.16),
                      item.color.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: item.color.withValues(alpha: 0.16)),
                ),
                child: Icon(item.icon, color: item.color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: item.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: item.color.withValues(alpha: 0.16),
                            ),
                          ),
                          child: Text(
                            item.roleLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: item.color,
                              fontWeight: FontWeight.w900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CoursePill(label: 'Course ${item.courseId}'),
                        _CoursePill(label: item.courseName),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primaryDark,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoursePill extends StatelessWidget {
  final String label;

  const _CoursePill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
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
    return PolishedStateCard(
      icon: icon,
      title: title,
      message: subtitle,
      color: icon == Icons.search_off_rounded
          ? AppColors.warning
          : AppColors.primary,
    );
  }
}
