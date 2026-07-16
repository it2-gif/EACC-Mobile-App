import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/chat_thread_resolver.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/screen_header.dart';
import '../widgets/unread_badge.dart';
import 'chat_screen.dart';

class AdminInboxScreen extends StatefulWidget {
  final AuthSession session;

  const AdminInboxScreen({super.key, required this.session});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  static const _pageSize = 5;

  final searchController = TextEditingController();
  final List<AdminInboxThread> _threads = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  _InboxFilter _filter = _InboxFilter.all;
  String _searchQuery = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  Map<String, Course> get _coursesById => {
    for (final course in widget.session.courses) course.id: course,
  };

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

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
    final visibleThreads = _filteredThreads;
    final filterCounts = _filterCounts;

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
            _InboxSummary(
              loadedCount: _threads.length,
              visibleCount: visibleThreads.length,
              unreadCount: _threads.fold(
                0,
                (total, thread) => total + thread.adminUnreadCount,
              ),
            ),
            const SizedBox(height: 12),
            _InboxControls(
              controller: searchController,
              selectedFilter: _filter,
              filterCounts: filterCounts,
              onFilterChanged: (filter) => setState(() => _filter = filter),
              onSearchChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
            const SizedBox(height: 12),
            if (visibleThreads.isEmpty)
              _FilteredInboxEmptyState(
                hasMore: _hasMore,
                onLoadMore: () => _load(reset: false),
              )
            else
              ...visibleThreads.map(
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

  List<AdminInboxThread> get _filteredThreads {
    final query = _searchQuery.trim().toLowerCase();

    return _threads
        .where((thread) {
          if (!_matchesFilter(thread)) return false;
          if (query.isEmpty) return true;

          final course = _coursesById[thread.courseId];
          return _matchesSearch(thread, course, query);
        })
        .toList(growable: false);
  }

  Map<_InboxFilter, int> get _filterCounts {
    return {
      for (final filter in _InboxFilter.values)
        filter: _threads
            .where((thread) => _matchesSpecificFilter(thread, filter))
            .length,
    };
  }

  bool _matchesFilter(AdminInboxThread thread) {
    return _matchesSpecificFilter(thread, _filter);
  }

  bool _matchesSpecificFilter(AdminInboxThread thread, _InboxFilter filter) {
    return switch (filter) {
      _InboxFilter.all => true,
      _InboxFilter.unread => thread.adminUnreadCount > 0,
      _InboxFilter.teacherChats =>
        thread.isTeacherChat || thread.isStudentTeacherChat,
      _InboxFilter.contactPersonChats => thread.isContactPersonChat,
      _InboxFilter.announcements => thread.isAnnouncement,
    };
  }

  bool _matchesSearch(AdminInboxThread thread, Course? course, String query) {
    final values = [
      thread.courseId,
      course?.displayTitle,
      course?.category,
      course?.teacherName,
      course?.keyPersonName,
      _threadTitle(thread, course),
      _resolvedStudentName(thread, course),
      thread.title,
      thread.lastMessage,
      thread.lastSenderName,
      thread.lastSenderRole,
    ];

    return values.whereType<String>().any(
      (value) => value.toLowerCase().contains(query),
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

enum _InboxFilter {
  all('All', Icons.all_inbox_rounded),
  unread('Unread', Icons.mark_chat_unread_rounded),
  teacherChats('Teacher chats', Icons.school_rounded),
  contactPersonChats('Contact-person chats', Icons.verified_user_rounded),
  announcements('Announcements', Icons.campaign_rounded);

  final String label;
  final IconData icon;

  const _InboxFilter(this.label, this.icon);
}

class _InboxSummary extends StatelessWidget {
  final int loadedCount;
  final int visibleCount;
  final int unreadCount;

  const _InboxSummary({
    required this.loadedCount,
    required this.visibleCount,
    required this.unreadCount,
  });

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Newest chats, loaded in small batches',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$visibleCount visible from $loadedCount loaded chats.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            UnreadBadge(count: unreadCount, compact: true),
          ],
        ],
      ),
    );
  }
}

class _InboxControls extends StatelessWidget {
  final TextEditingController controller;
  final _InboxFilter selectedFilter;
  final Map<_InboxFilter, int> filterCounts;
  final ValueChanged<_InboxFilter> onFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _InboxControls({
    required this.controller,
    required this.selectedFilter,
    required this.filterCounts,
    required this.onFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Search inbox',
                hintText: 'Course ID, course name, student, teacher...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filter in _InboxFilter.values)
                  FilterChip(
                    selected: selectedFilter == filter,
                    avatar: Icon(filter.icon, size: 17),
                    label: Text(
                      '${filter.label} (${filterCounts[filter] ?? 0})',
                    ),
                    onSelected: (_) => onFilterChanged(filter),
                    showCheckmark: false,
                    selectedColor: AppColors.primary.withValues(alpha: 0.14),
                    side: BorderSide(
                      color: selectedFilter == filter
                          ? AppColors.primary.withValues(alpha: 0.34)
                          : AppColors.border,
                    ),
                    labelStyle: TextStyle(
                      color: selectedFilter == filter
                          ? AppColors.primaryDark
                          : AppColors.muted,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilteredInboxEmptyState extends StatelessWidget {
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _FilteredInboxEmptyState({
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    return PolishedStateCard(
      icon: Icons.filter_alt_off_rounded,
      title: 'No matching loaded chats',
      message: hasMore
          ? 'Try another filter or load more recent chats to continue searching.'
          : 'Try another filter or search term.',
      color: AppColors.warning,
      actionLabel: hasMore ? 'Load 5 more' : null,
      onAction: hasMore ? onLoadMore : null,
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
    final courseName = course?.displayTitle ?? 'Course ${thread.courseId}';
    final compact = MediaQuery.sizeOf(context).width < 390;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!compact) ...[
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
              ],
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
                          UnreadBadge(
                            count: thread.adminUnreadCount,
                            compact: true,
                          ),
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
              if (!compact) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
              ],
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
      ? ChatThreadResolver.studentIdFromContactPersonThreadId(thread.threadId)
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
