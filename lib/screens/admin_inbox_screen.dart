import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/screen_header.dart';
import 'chat_screen.dart';

class AdminInboxScreen extends StatefulWidget {
  final AuthSession session;

  const AdminInboxScreen({super.key, required this.session});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  static const _pageSize = 5;

  final List<AdminInboxThread> _threads = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  Map<String, Course> get _coursesById => {
    for (final course in widget.session.courses) course.id: course,
  };

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _cursor = null;
        _threads.clear();
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final page = await FirestoreChatService.getAdminInboxPage(
        pageSize: _pageSize,
        startAfter: reset ? null : _cursor,
      );
      if (!mounted) return;

      final allowedCourseIds = widget.session.courses
          .map((course) => course.id)
          .toSet();
      final items = widget.session.appUser.canViewAllCourses
          ? page.items
          : page.items
                .where((thread) => allowedCourseIds.contains(thread.courseId))
                .toList(growable: false);

      setState(() {
        _threads.addAll(items);
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Admin Inbox',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          ScreenHeader(
            title: 'Admin Inbox',
            subtitle: 'Newest active chats across your visible courses.',
            icon: Icons.mark_chat_unread_rounded,
          ),
          const SizedBox(height: 16),
          if (_loading && _threads.isEmpty)
            const PolishedLoadingCard(
              title: 'Loading recent chats',
              message: 'Fetching the newest 5 chat summaries only.',
            )
          else if (_error != null && _threads.isEmpty)
            PolishedStateCard(
              icon: Icons.error_outline_rounded,
              title: 'Could not load inbox',
              message: _error!,
              color: AppColors.danger,
              actionLabel: 'Retry',
              onAction: () => _load(reset: true),
            )
          else if (_threads.isEmpty)
            const PolishedStateCard(
              icon: Icons.forum_outlined,
              title: 'No active chats yet',
              message:
                  'Chats with messages will appear here from newest to oldest.',
              color: AppColors.primary,
            )
          else ...[
            _InboxSummary(count: _threads.length),
            const SizedBox(height: 12),
            ..._threads.map(
              (thread) => _AdminInboxTile(
                thread: thread,
                course: _coursesById[thread.courseId],
                onTap: () => _openThread(thread),
              ),
            ),
            const SizedBox(height: 12),
            _LoadMoreInboxCard(
              loaded: _threads.length,
              hasMore: _hasMore,
              loading: _loadingMore,
              onLoadMore: () => _load(reset: false),
            ),
          ],
        ],
      ),
    );
  }

  void _openThread(AdminInboxThread thread) {
    final course = _coursesById[thread.courseId];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: _threadTitle(thread, course),
          currentUserRole: 'admin',
          courseId: thread.courseId,
          threadId: thread.threadId,
          senderName: widget.session.appUser.name,
          threadStudentName: _resolvedStudentName(thread, course),
          isSuperAdmin: widget.session.appUser.isSuperAdmin,
          canManageAllMessages: widget.session.appUser.canViewAllCourses,
        ),
      ),
    );
  }
}

class _InboxSummary extends StatelessWidget {
  final int count;

  const _InboxSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.dynamic_feed_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Showing $count loaded chats. Use Load more to keep reads light.',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminInboxTile extends StatelessWidget {
  final AdminInboxThread thread;
  final Course? course;
  final VoidCallback onTap;

  const _AdminInboxTile({
    required this.thread,
    required this.course,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _threadColor(thread);
    final courseName = course?.displayName ?? 'Course ${thread.courseId}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_threadIcon(thread), color: color, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _threadTitle(thread, course),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (thread.adminUnreadCount > 0) ...[
                          const SizedBox(width: 8),
                          _UnreadBadge(count: thread.adminUnreadCount),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$courseName - Course ${thread.courseId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_senderLabel(thread)}: ${thread.lastMessage}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        _TypePill(label: _threadType(thread), color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formatThreadTime(thread.lastMessageAt),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypePill extends StatelessWidget {
  final String label;
  final Color color;

  const _TypePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count new',
        style: const TextStyle(
          color: AppColors.danger,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LoadMoreInboxCard extends StatelessWidget {
  final int loaded;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  const _LoadMoreInboxCard({
    required this.loaded,
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (hasMore) {
      return OutlinedButton.icon(
        onPressed: loading ? null : onLoadMore,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more_rounded),
        label: Text(loading ? 'Loading...' : 'Load 5 more chats'),
      );
    }

    return PolishedStateCard(
      icon: Icons.done_all_rounded,
      title: 'All loaded chats are shown',
      message: 'You have loaded $loaded recent active chats.',
      color: AppColors.success,
    );
  }
}

String _threadTitle(AdminInboxThread thread, Course? course) {
  if (thread.isAnnouncement) return 'Announcement chat';
  if (thread.isTeacherChat) {
    final teacher = course?.teacherName?.trim();
    return teacher == null || teacher.isEmpty ? 'Teacher chat' : teacher;
  }
  if (thread.isContactPersonChat) {
    final student = _resolvedStudentName(thread, course) ?? '';
    final contact = course?.keyPersonName?.trim();
    final target = contact == null || contact.isEmpty
        ? 'Contact person'
        : contact;
    return student.isEmpty ? target : '$student - $target';
  }

  final student = _resolvedStudentName(thread, course) ?? '';
  final teacher = course?.teacherName?.trim();
  final target = teacher == null || teacher.isEmpty ? 'Teacher' : teacher;
  return student.isEmpty ? target : '$student - $target';
}

String? _resolvedStudentName(AdminInboxThread thread, Course? course) {
  final explicitName = thread.studentName.trim();
  if (explicitName.isNotEmpty) return explicitName;

  final studentId = thread.isContactPersonChat
      ? FirestoreChatService.keyPersonStudentLmsUserId(thread.threadId)
      : thread.threadId;
  final normalizedStudentId = studentId?.trim();
  if (normalizedStudentId == null || normalizedStudentId.isEmpty) return null;

  for (final student in course?.students ?? const <CourseStudent>[]) {
    if (student.id == normalizedStudentId) return student.name;
  }

  return null;
}

String _threadType(AdminInboxThread thread) {
  if (thread.isAnnouncement) return 'Announcement';
  if (thread.isTeacherChat) return 'Teacher';
  if (thread.isContactPersonChat) return 'Contact person';
  return 'Student';
}

String _senderLabel(AdminInboxThread thread) {
  final role = thread.lastSenderRole.trim();
  final name = thread.lastSenderName.trim();
  if (name.isEmpty || name.toLowerCase() == 'unknown') {
    return role.isEmpty ? 'Sender' : role;
  }
  return role.isEmpty ? name : '$name ($role)';
}

IconData _threadIcon(AdminInboxThread thread) {
  if (thread.isAnnouncement) return Icons.campaign_rounded;
  if (thread.isTeacherChat) return Icons.admin_panel_settings_rounded;
  if (thread.isContactPersonChat) return Icons.verified_user_rounded;
  return Icons.chat_bubble_rounded;
}

Color _threadColor(AdminInboxThread thread) {
  if (thread.isAnnouncement) return AppColors.admin;
  if (thread.isTeacherChat) return AppColors.teacher;
  if (thread.isContactPersonChat) return AppColors.admin;
  return AppColors.primary;
}
