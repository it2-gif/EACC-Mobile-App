import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/admin_api.dart';
import '../services/chat_thread_resolver.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/support_entry_card.dart';
import '../widgets/unread_badge.dart';
import 'admin_analysis_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_inbox_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_threads_screen.dart';
import 'admin_users_screen.dart';
import 'chat_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  final AuthSession session;

  const AdminDashboardScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = session.appUser.isSuperAdmin;
    final canSeeAnalysis =
        session.appUser.isSuperAdmin || session.appUser.isTechnicalSupport;
    final insights = _DashboardInsights.fromSession(session);
    final adminUnreadCourseIds = _adminUnreadCourseIds(session);
    final quickActions = <Widget>[
      if (canSeeAnalysis)
        _NavTile(
          icon: Icons.analytics_rounded,
          title: 'Analysis',
          subtitle: 'View courses, chats, messages, uploads, and usage totals',
          color: const Color(0xFF6A3DE8),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminAnalysisScreen(session: session),
            ),
          ),
        ),
      if (!isSuperAdmin)
        _NavTile(
          icon: Icons.menu_book_rounded,
          title: 'Courses',
          subtitle: session.appUser.canViewAllCourses
              ? 'Search courses and open student chats'
              : 'Open your linked courses and student chats',
          color: AppColors.primary,
          unreadStream: FirestoreChatService.getAdminUnreadTotalForCourses(
            adminUnreadCourseIds,
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminCoursesScreen(session: session),
            ),
          ),
        ),
      _NavTile(
        icon: Icons.campaign_rounded,
        title: 'Announcements',
        subtitle: 'Send course announcements or private student messages',
        color: AppColors.admin,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminAnnouncementsScreen(session: session),
          ),
        ),
      ),
      if (session.appUser.isSuperAdmin)
        _NavTile(
          icon: Icons.mark_chat_unread_rounded,
          title: 'Admin Inbox',
          subtitle: 'Review newest active chats from all visible courses',
          color: AppColors.primaryDark,
          unreadStream: FirestoreChatService.getAdminUnreadTotalForCourses(
            adminUnreadCourseIds,
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminInboxScreen(session: session),
            ),
          ),
        ),
      if (session.appUser.isSuperAdmin)
        _NavTile(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Moderations',
          subtitle: 'Search and soft-delete selected messages',
          color: AppColors.danger,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminModerationScreen(session: session),
            ),
          ),
        ),
      if (session.appUser.isSuperAdmin)
        _NavTile(
          icon: Icons.history_edu_rounded,
          title: 'Deleted Messages',
          subtitle: 'Review deleted messages and moderation history',
          color: AppColors.primaryDark,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminAuditScreen(session: session),
            ),
          ),
        ),
    ];

    return AppScaffold(
      title: 'EACC Admin',
      showLogout: true,
      floatingActionButton: SupportHelpButton(session: session),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Welcome header
          _WelcomeHeader(
            name: session.appUser.name,
            isSuperAdmin: session.appUser.isSuperAdmin,
            isManagerOperation: session.appUser.isManagerOperation,
            canViewAllCourses: session.appUser.canViewAllCourses,
          ),
          const SizedBox(height: 14),
          _TodayOverviewSection(insights: insights),
          const SizedBox(height: 24),
          _QuickActionsSection(
            title: session.appUser.isSuperAdmin
                ? 'Quick actions'
                : 'Course actions',
            subtitle: session.appUser.isSuperAdmin
                ? 'Jump to the highest-value admin workflows.'
                : 'Open the course tools available to your account.',
            actions: quickActions,
          ),
          const SizedBox(height: 24),
          if (session.appUser.isSuperAdmin) ...[
            _AdminLiveInboxPanels(session: session),
            const SizedBox(height: 24),
            _CoursesNeedingSetupSection(session: session),
            const SizedBox(height: 24),
          ],
          if (!session.appUser.isManagerOperation) ...[
            _CourseActivityPanel(session: session),
            const SizedBox(height: 24),
          ],
          _AttentionNeededSection(session: session, insights: insights),
          const SizedBox(height: 24),
          if (isSuperAdmin) ...[
            _FullAccessControlCenter(session: session),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

Iterable<String> _adminUnreadCourseIds(AuthSession session) {
  if (!session.appUser.isManagerOperation || session.appUser.isSuperAdmin) {
    return session.courses.map((course) => course.id);
  }

  final adminId = session.lmsUser.lmsUserId.trim().toLowerCase();
  final adminName = session.appUser.name.trim().toLowerCase();

  return session.courses
      .where((course) {
        final keyPersonId = course.keyPersonLmsUserId?.trim().toLowerCase();
        final keyPersonName = course.keyPersonName?.trim().toLowerCase();

        return (adminId.isNotEmpty && keyPersonId == adminId) ||
            (adminName.isNotEmpty && keyPersonName == adminName);
      })
      .map((course) => course.id);
}

// ─── Welcome header ─────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  final String name;
  final bool isSuperAdmin;
  final bool isManagerOperation;
  final bool canViewAllCourses;

  const _WelcomeHeader({
    required this.name,
    required this.isSuperAdmin,
    required this.isManagerOperation,
    required this.canViewAllCourses,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 720;

    return Container(
      padding: EdgeInsets.all(wide ? 24 : 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF286FBE), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: wide ? 58 : 52,
            height: wide ? 58 : 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $name',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: wide ? 22 : 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSuperAdmin
                      ? 'EACC Super Administrator'
                      : isManagerOperation
                      ? 'EACC Manager Operation'
                      : 'EACC Contact-Person Administrator',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSuperAdmin
                            ? Icons.verified_user_rounded
                            : canViewAllCourses
                            ? Icons.manage_accounts_rounded
                            : Icons.link_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSuperAdmin
                            ? 'Full access enabled'
                            : canViewAllCourses
                            ? 'All courses visible'
                            : 'Linked courses only',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Live stat cards ─────────────────────────────────────────────────────────

class _DashboardInsights {
  final int courses;
  final int studentSeats;
  final int uniqueStudents;
  final int teachers;
  final int contactPeople;
  final int missingTeachers;
  final int missingContactPeople;
  final int emptyRosters;
  final int genericCourseNames;

  const _DashboardInsights({
    required this.courses,
    required this.studentSeats,
    required this.uniqueStudents,
    required this.teachers,
    required this.contactPeople,
    required this.missingTeachers,
    required this.missingContactPeople,
    required this.emptyRosters,
    required this.genericCourseNames,
  });

  factory _DashboardInsights.fromSession(AuthSession session) {
    final studentIds = <String>{};
    final teacherNames = <String>{};
    final contactPeople = <String>{};
    var studentSeats = 0;
    var missingTeachers = 0;
    var missingContactPeople = 0;
    var emptyRosters = 0;
    var genericCourseNames = 0;

    for (final course in session.courses) {
      studentSeats += course.students.length;
      for (final student in course.students) {
        final id = student.id.trim();
        if (id.isNotEmpty) studentIds.add(id);
      }

      final teacher = course.teacherName?.trim();
      if (teacher == null || teacher.isEmpty) {
        missingTeachers++;
      } else {
        teacherNames.add(teacher.toLowerCase());
      }

      final contactId = course.keyPersonLmsUserId?.trim();
      final contactName = course.keyPersonName?.trim();
      if ((contactId == null || contactId.isEmpty) &&
          (contactName == null || contactName.isEmpty)) {
        missingContactPeople++;
      } else {
        contactPeople.add(
          (contactId?.isNotEmpty == true ? contactId : contactName)!
              .toLowerCase(),
        );
      }

      if (course.students.isEmpty) emptyRosters++;
      if (course.displayName.trim().toLowerCase() == 'course ${course.id}') {
        genericCourseNames++;
      }
    }

    return _DashboardInsights(
      courses: session.courses.length,
      studentSeats: studentSeats,
      uniqueStudents: studentIds.length,
      teachers: teacherNames.length,
      contactPeople: contactPeople.length,
      missingTeachers: missingTeachers,
      missingContactPeople: missingContactPeople,
      emptyRosters: emptyRosters,
      genericCourseNames: genericCourseNames,
    );
  }

  int get attentionCount =>
      missingTeachers +
      missingContactPeople +
      emptyRosters +
      genericCourseNames;
}

class _TodayOverviewSection extends StatelessWidget {
  final _DashboardInsights insights;

  const _TodayOverviewSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    return _DashboardSection(
      title: "Today's overview",
      subtitle: 'The most important LMS structure numbers at a glance.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 880
              ? 4
              : constraints.maxWidth >= 620
              ? 2
              : 1;
          final itemWidth =
              (constraints.maxWidth - (columns - 1) * 12) / columns;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: itemWidth,
                child: _OverviewCard(
                  icon: Icons.menu_book_rounded,
                  label: 'Courses',
                  value: insights.courses,
                  helper: 'Available to this admin',
                  color: AppColors.primary,
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _OverviewCard(
                  icon: Icons.school_rounded,
                  label: 'Students',
                  value: insights.uniqueStudents,
                  helper: '${insights.studentSeats} course seats',
                  color: AppColors.student,
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _OverviewCard(
                  icon: Icons.auto_stories_rounded,
                  label: 'Teachers',
                  value: insights.teachers,
                  helper: '${insights.contactPeople} contact people',
                  color: AppColors.teacher,
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: _OverviewCard(
                  icon: Icons.health_and_safety_rounded,
                  label: 'Needs review',
                  value: insights.attentionCount,
                  helper: 'Data health checks',
                  color: insights.attentionCount == 0
                      ? AppColors.success
                      : AppColors.admin,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final String helper;
  final Color color;

  const _OverviewCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.16),
                    color.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: color.withValues(alpha: 0.14)),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      color: color,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _AdminLiveInboxPanels extends StatefulWidget {
  final AuthSession session;

  const _AdminLiveInboxPanels({required this.session});

  @override
  State<_AdminLiveInboxPanels> createState() => _AdminLiveInboxPanelsState();
}

class _AdminLiveInboxPanelsState extends State<_AdminLiveInboxPanels> {
  late Future<AdminInboxPage> _future;

  Map<String, Course> get _coursesById => {
    for (final course in widget.session.courses) course.id: course,
  };

  @override
  void initState() {
    super.initState();
    _future = _loadInbox();
  }

  Future<AdminInboxPage> _loadInbox() {
    return FirestoreChatService.getAdminInboxPage(pageSize: 8);
  }

  void _refresh() {
    setState(() {
      _future = _loadInbox();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminInboxPage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PolishedLoadingCard(
            title: 'Loading live inbox',
            message: 'Preparing newest conversations for the dashboard.',
          );
        }

        if (snapshot.hasError) {
          return PolishedStateCard(
            icon: Icons.error_outline_rounded,
            title: 'Could not load live inbox',
            message: snapshot.error.toString(),
            color: AppColors.danger,
            actionLabel: 'Retry',
            onAction: _refresh,
          );
        }

        final threads = snapshot.data?.items ?? const <AdminInboxThread>[];
        final recent = threads.take(3).toList(growable: false);
        final unread = threads
            .where((thread) => thread.adminUnreadCount > 0)
            .take(3)
            .toList(growable: false);

        return _DashboardSection(
          title: 'Live conversations',
          subtitle:
              'Newest activity and unread admin work, loaded from the shared inbox.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 860;
              final panels = [
                _InboxPreviewPanel(
                  title: 'Recent activity',
                  subtitle: 'Newest active chats',
                  icon: Icons.bolt_rounded,
                  color: AppColors.primary,
                  threads: recent,
                  coursesById: _coursesById,
                  emptyTitle: 'No recent activity yet',
                  emptyMessage: 'Chats with messages will appear here.',
                  onOpenThread: _openThread,
                  onOpenInbox: _openInbox,
                ),
                _InboxPreviewPanel(
                  title: 'Unread conversations',
                  subtitle: 'Needs admin attention',
                  icon: Icons.mark_chat_unread_rounded,
                  color: AppColors.danger,
                  threads: unread,
                  coursesById: _coursesById,
                  emptyTitle: 'Inbox is clear',
                  emptyMessage: 'No unread admin conversations are loaded.',
                  onOpenThread: _openThread,
                  onOpenInbox: _openInbox,
                ),
              ];

              if (!wide) {
                return Column(
                  children: [panels[0], const SizedBox(height: 12), panels[1]],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: panels[0]),
                  const SizedBox(width: 12),
                  Expanded(child: panels[1]),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _openInbox() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminInboxScreen(session: widget.session),
      ),
    );
  }

  void _openThread(AdminInboxThread thread) {
    final course = _coursesById[thread.courseId];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          title: _dashboardThreadTitle(thread, course),
          currentUserRole: 'admin',
          courseId: thread.courseId,
          threadId: thread.threadId,
          senderName: widget.session.appUser.name,
          threadStudentName: _dashboardStudentName(thread, course),
          isSuperAdmin: widget.session.appUser.isSuperAdmin,
          canManageAllMessages: widget.session.appUser.canViewAllCourses,
        ),
      ),
    );
  }
}

class _InboxPreviewPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<AdminInboxThread> threads;
  final Map<String, Course> coursesById;
  final String emptyTitle;
  final String emptyMessage;
  final ValueChanged<AdminInboxThread> onOpenThread;
  final VoidCallback onOpenInbox;

  const _InboxPreviewPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.threads,
    required this.coursesById,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onOpenThread,
    required this.onOpenInbox,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.16),
                        color.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.14)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onOpenInbox,
                  child: const Text('Open inbox'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (threads.isEmpty)
              _InlineState(
                icon: Icons.inbox_rounded,
                message: '$emptyTitle. $emptyMessage',
                color: color,
              )
            else
              ...threads.map(
                (thread) => _InboxPreviewRow(
                  thread: thread,
                  course: coursesById[thread.courseId],
                  onTap: () => onOpenThread(thread),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InboxPreviewRow extends StatelessWidget {
  final AdminInboxThread thread;
  final Course? course;
  final VoidCallback onTap;

  const _InboxPreviewRow({
    required this.thread,
    required this.course,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _dashboardThreadColor(thread);
    final courseName = course?.displayName ?? 'Course ${thread.courseId}';
    final compact = MediaQuery.sizeOf(context).width < 390;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(_dashboardThreadIcon(thread), color: color),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _dashboardThreadTitle(thread, course),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w900,
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
                      const SizedBox(height: 3),
                      Text(
                        '$courseName - Course ${thread.courseId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        thread.lastMessage.isEmpty
                            ? 'No message preview'
                            : '${_dashboardSenderLabel(thread)}: ${thread.lastMessage}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          _DashboardThreadPill(
                            label: _dashboardThreadType(thread),
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formatThreadTime(thread.lastMessageAt),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
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
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.muted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardThreadPill extends StatelessWidget {
  final String label;
  final Color color;

  const _DashboardThreadPill({required this.label, required this.color});

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
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

String _dashboardThreadTitle(AdminInboxThread thread, Course? course) {
  if (thread.isAnnouncement) return 'Announcement chat';
  if (thread.isTeacherChat) {
    final teacher = course?.teacherName?.trim();
    return teacher == null || teacher.isEmpty ? 'Teacher chat' : teacher;
  }
  if (thread.isContactPersonChat) {
    final student = _dashboardStudentName(thread, course) ?? '';
    final contact = course?.keyPersonName?.trim();
    final target = contact == null || contact.isEmpty
        ? 'Contact person'
        : contact;
    return student.isEmpty ? target : '$student - $target';
  }

  final student = _dashboardStudentName(thread, course) ?? '';
  final teacher = course?.teacherName?.trim();
  final target = teacher == null || teacher.isEmpty ? 'Teacher' : teacher;
  return student.isEmpty ? target : '$student - $target';
}

String? _dashboardStudentName(AdminInboxThread thread, Course? course) {
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

String _dashboardThreadType(AdminInboxThread thread) {
  if (thread.isAnnouncement) return 'Announcement';
  if (thread.isTeacherChat) return 'Teacher';
  if (thread.isContactPersonChat) return 'Contact person';
  return 'Student';
}

String _dashboardSenderLabel(AdminInboxThread thread) {
  final role = thread.lastSenderRole.trim();
  final name = thread.lastSenderName.trim();
  if (name.isEmpty || name.toLowerCase() == 'unknown') {
    return role.isEmpty ? 'Sender' : role;
  }
  return role.isEmpty ? name : '$name ($role)';
}

IconData _dashboardThreadIcon(AdminInboxThread thread) {
  if (thread.isAnnouncement) return Icons.campaign_rounded;
  if (thread.isTeacherChat) return Icons.admin_panel_settings_rounded;
  if (thread.isContactPersonChat) return Icons.verified_user_rounded;
  return Icons.chat_bubble_rounded;
}

Color _dashboardThreadColor(AdminInboxThread thread) {
  if (thread.isAnnouncement) return AppColors.admin;
  if (thread.isTeacherChat) return AppColors.teacher;
  if (thread.isContactPersonChat) return AppColors.admin;
  return AppColors.primary;
}

enum _CourseIssueType {
  missingTeacher(
    'Missing teacher',
    'Courses missing teacher',
    'Teacher name should appear in every course chat.',
    Icons.person_search_rounded,
    AppColors.teacher,
  ),
  missingContact(
    'Missing contact',
    'Courses missing contact person',
    'Contact-person mapping controls scoped admin access.',
    Icons.admin_panel_settings_rounded,
    AppColors.admin,
  ),
  emptyRoster(
    'Empty rosters',
    'Courses with no students',
    'Empty rosters may mean LMS sync or course setup needs review.',
    Icons.group_off_rounded,
    AppColors.danger,
  ),
  genericName(
    'Generic names',
    'Generic course names',
    'Clear course names make search and reports easier.',
    Icons.label_off_rounded,
    Color(0xFF6A3DE8),
  );

  final String shortLabel;
  final String title;
  final String helper;
  final IconData icon;
  final Color color;

  const _CourseIssueType(
    this.shortLabel,
    this.title,
    this.helper,
    this.icon,
    this.color,
  );
}

class _CourseIssue {
  final Course course;
  final _CourseIssueType type;

  const _CourseIssue({required this.course, required this.type});
}

List<_CourseIssue> _courseIssuesFor(
  AuthSession session, [
  _CourseIssueType? filter,
]) {
  final issues = <_CourseIssue>[];

  for (final course in session.courses) {
    for (final type in _CourseIssueType.values) {
      if (filter != null && type != filter) continue;
      if (_courseMatchesIssue(course, type)) {
        issues.add(_CourseIssue(course: course, type: type));
      }
    }
  }

  issues.sort((a, b) {
    final typeCompare = a.type.index.compareTo(b.type.index);
    if (typeCompare != 0) return typeCompare;
    return a.course.displayName.toLowerCase().compareTo(
      b.course.displayName.toLowerCase(),
    );
  });

  return issues;
}

bool _courseMatchesIssue(Course course, _CourseIssueType type) {
  return switch (type) {
    _CourseIssueType.missingTeacher => _isBlank(course.teacherName),
    _CourseIssueType.missingContact =>
      _isBlank(course.keyPersonLmsUserId) && _isBlank(course.keyPersonName),
    _CourseIssueType.emptyRoster => course.students.isEmpty,
    _CourseIssueType.genericName => _isGenericCourseName(course),
  };
}

bool _isBlank(String? value) => value == null || value.trim().isEmpty;

bool _isGenericCourseName(Course course) {
  final courseId = course.id.trim().toLowerCase();
  final rawName = course.name.trim().toLowerCase();
  final displayName = course.displayName.trim().toLowerCase();

  return rawName == 'course $courseId' || displayName == 'course $courseId';
}

class _CoursesNeedingSetupSection extends StatelessWidget {
  final AuthSession session;

  const _CoursesNeedingSetupSection({required this.session});

  @override
  Widget build(BuildContext context) {
    final issues = _courseIssuesFor(session);
    final preview = issues.take(4).toList(growable: false);

    return _DashboardSection(
      title: 'Courses needing setup',
      subtitle: 'The exact courses behind the health checks.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: issues.isEmpty
              ? const _InlineState(
                  icon: Icons.verified_rounded,
                  message: 'All loaded courses have the core setup data.',
                  color: AppColors.success,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppColors.admin.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.construction_rounded,
                            color: AppColors.admin,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${issues.length} setup ${issues.length == 1 ? 'issue' : 'issues'} found',
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Review missing mappings before they become support tickets.',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openIssueScreen(context, session),
                          child: const Text('View all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (var index = 0; index < preview.length; index++)
                      _CourseIssuePreviewRow(
                        issue: preview[index],
                        isLast: index == preview.length - 1,
                        onTap: () => _openIssueScreen(
                          context,
                          session,
                          initialType: preview[index].type,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CourseIssuePreviewRow extends StatelessWidget {
  final _CourseIssue issue;
  final bool isLast;
  final VoidCallback onTap;

  const _CourseIssuePreviewRow({
    required this.issue,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Material(
        color: issue.type.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: issue.type.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    issue.type.icon,
                    color: issue.type.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue.course.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${issue.type.shortLabel} - Course ${issue.course.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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
      ),
    );
  }
}

void _openIssueScreen(
  BuildContext context,
  AuthSession session, {
  _CourseIssueType? initialType,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          _CourseIssuesScreen(session: session, initialType: initialType),
    ),
  );
}

class _CourseIssuesScreen extends StatefulWidget {
  final AuthSession session;
  final _CourseIssueType? initialType;

  const _CourseIssuesScreen({required this.session, this.initialType});

  @override
  State<_CourseIssuesScreen> createState() => _CourseIssuesScreenState();
}

class _CourseIssuesScreenState extends State<_CourseIssuesScreen> {
  _CourseIssueType? selectedType;

  @override
  void initState() {
    super.initState();
    selectedType = widget.initialType;
  }

  @override
  Widget build(BuildContext context) {
    final issues = _courseIssuesFor(widget.session, selectedType);
    final title = selectedType?.title ?? 'Course setup issues';

    return AppScaffold(
      title: title,
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _IssueScreenHeader(
            title: title,
            count: issues.length,
            selectedType: selectedType,
          ),
          const SizedBox(height: 14),
          _IssueFilterBar(
            selectedType: selectedType,
            onChanged: (type) => setState(() => selectedType = type),
          ),
          const SizedBox(height: 14),
          if (issues.isEmpty)
            PolishedStateCard(
              icon: Icons.verified_rounded,
              title: 'No matching issues',
              message: selectedType == null
                  ? 'All loaded courses have the core setup data.'
                  : 'No courses match this health check.',
              color: AppColors.success,
            )
          else
            ...issues.map(
              (issue) => _CourseIssueDetailCard(
                issue: issue,
                onOpenCourse: () => _openCourseThreads(context, issue.course),
              ),
            ),
        ],
      ),
    );
  }

  void _openCourseThreads(BuildContext context, Course course) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminThreadsScreen(
          courseId: course.id,
          courseName: course.displayName,
          teacherName: course.teacherName,
          keyPersonName: course.keyPersonName,
          students: course.students,
          session: widget.session,
        ),
      ),
    );
  }
}

class _IssueScreenHeader extends StatelessWidget {
  final String title;
  final int count;
  final _CourseIssueType? selectedType;

  const _IssueScreenHeader({
    required this.title,
    required this.count,
    required this.selectedType,
  });

  @override
  Widget build(BuildContext context) {
    final color = selectedType?.color ?? AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.96), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(
              selectedType?.icon ?? Icons.health_and_safety_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? 'course needs' : 'courses need'} review',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueFilterBar extends StatelessWidget {
  final _CourseIssueType? selectedType;
  final ValueChanged<_CourseIssueType?> onChanged;

  const _IssueFilterBar({required this.selectedType, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              selected: selectedType == null,
              showCheckmark: false,
              avatar: const Icon(Icons.all_inbox_rounded, size: 17),
              label: const Text('All issues'),
              onSelected: (_) => onChanged(null),
            ),
            for (final type in _CourseIssueType.values)
              FilterChip(
                selected: selectedType == type,
                showCheckmark: false,
                avatar: Icon(type.icon, size: 17),
                label: Text(type.shortLabel),
                onSelected: (_) => onChanged(type),
              ),
          ],
        ),
      ),
    );
  }
}

class _CourseIssueDetailCard extends StatelessWidget {
  final _CourseIssue issue;
  final VoidCallback onOpenCourse;

  const _CourseIssueDetailCard({
    required this.issue,
    required this.onOpenCourse,
  });

  @override
  Widget build(BuildContext context) {
    final course = issue.course;
    final compact = MediaQuery.sizeOf(context).width < 420;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: issue.type.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(issue.type.icon, color: issue.type.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Course ${course.id} - ${issue.type.title}',
                        style: TextStyle(
                          color: issue.type.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _IssueMetaChip(
                  icon: Icons.person_outline_rounded,
                  label: _isBlank(course.teacherName)
                      ? 'No teacher'
                      : course.teacherName!.trim(),
                  color: AppColors.teacher,
                ),
                _IssueMetaChip(
                  icon: Icons.verified_user_rounded,
                  label: _isBlank(course.keyPersonName)
                      ? 'No contact'
                      : course.keyPersonName!.trim(),
                  color: AppColors.admin,
                ),
                _IssueMetaChip(
                  icon: Icons.groups_rounded,
                  label:
                      '${course.students.length} ${course.students.length == 1 ? 'student' : 'students'}',
                  color: AppColors.student,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (compact) ...[
              Text(
                issue.type.helper,
                style: const TextStyle(
                  color: AppColors.muted,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpenCourse,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open course'),
                ),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      issue.type.helper,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: onOpenCourse,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _IssueMetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttentionNeededSection extends StatelessWidget {
  final AuthSession session;
  final _DashboardInsights insights;

  const _AttentionNeededSection({
    required this.session,
    required this.insights,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _AttentionItem(
        type: _CourseIssueType.missingTeacher,
        count: insights.missingTeachers,
      ),
      _AttentionItem(
        type: _CourseIssueType.missingContact,
        count: insights.missingContactPeople,
      ),
      _AttentionItem(
        type: _CourseIssueType.emptyRoster,
        count: insights.emptyRosters,
      ),
      _AttentionItem(
        type: _CourseIssueType.genericName,
        count: insights.genericCourseNames,
      ),
    ];

    return _DashboardSection(
      title: 'Attention needed',
      subtitle: 'Data-health signals that help admins fix problems early.',
      child: insights.attentionCount == 0
          ? const _HealthyAttentionCard()
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? 2 : 1;
                final width = columns == 2
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: items
                      .where((item) => item.count > 0)
                      .map(
                        (item) => SizedBox(
                          width: width,
                          child: _AttentionCard(
                            item,
                            onTap: () => _openIssueScreen(
                              context,
                              session,
                              initialType: item.type,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
    );
  }
}

class _AttentionItem {
  final _CourseIssueType type;
  final int count;

  const _AttentionItem({required this.type, required this.count});
}

class _AttentionCard extends StatelessWidget {
  final _AttentionItem item;
  final VoidCallback onTap;

  const _AttentionCard(this.item, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.type.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.type.icon, color: item.type.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.type.title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.type.helper,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${item.count}',
                style: TextStyle(
                  color: item.type.color,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
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

class _HealthyAttentionCard extends StatelessWidget {
  const _HealthyAttentionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.verified_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No immediate data issues',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Courses have teachers, contact people, and student rosters in this session.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
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

class _QuickActionsSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const _QuickActionsSection({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return _DashboardSection(
      title: title,
      subtitle: subtitle,
      child: _NavGrid(children: actions),
    );
  }
}

class _FullAccessControlCenter extends StatefulWidget {
  final AuthSession session;

  const _FullAccessControlCenter({required this.session});

  @override
  State<_FullAccessControlCenter> createState() =>
      _FullAccessControlCenterState();
}

class _FullAccessControlCenterState extends State<_FullAccessControlCenter> {
  final _api = AdminApi();
  AdminUsersCounts? _peopleCounts;

  @override
  void initState() {
    super.initState();
    _loadPeopleCounts();
  }

  Future<void> _loadPeopleCounts() async {
    try {
      final page = await _api.listUsers(take: 1);
      if (!mounted) return;
      setState(() => _peopleCounts = page.counts);
    } catch (_) {
      if (!mounted) return;
      setState(() => _peopleCounts = const AdminUsersCounts.empty());
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseStudentSeats = widget.session.courses.fold<int>(
      0,
      (total, course) => total + course.students.length,
    );
    final peopleCounts = _peopleCounts;

    return _DashboardSection(
      title: 'Control center',
      subtitle: 'Fast access to people, courses, and operational visibility.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 820;
          final cardWidth = twoColumns
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: cardWidth,
                child: _ControlCenterCard(
                  icon: Icons.groups_2_rounded,
                  title: 'People Dashboard',
                  subtitle:
                      'Search registered students, teachers, admins, and contact-person accounts.',
                  color: const Color(0xFF0E7C86),
                  stats: [
                    _ControlStat(label: 'Admins', value: peopleCounts?.admins),
                    _ControlStat(
                      label: 'Teachers',
                      value: peopleCounts?.teachers,
                    ),
                    _ControlStat(
                      label: 'Students',
                      value: peopleCounts?.students,
                    ),
                  ],
                  actionLabel: 'Open people',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminUsersScreen(session: widget.session),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: _ControlCenterCard(
                  icon: Icons.dashboard_customize_rounded,
                  title: 'Courses Dashboard',
                  subtitle:
                      'Find any course by ID, inspect rosters, and open chats.',
                  color: AppColors.primary,
                  stats: [
                    _ControlStat(
                      label: 'Courses',
                      value: widget.session.courses.length,
                    ),
                    _ControlStat(label: 'Chats', value: courseStudentSeats),
                    _ControlStat(
                      label: 'Directory',
                      value: widget.session.courses.length,
                    ),
                  ],
                  actionLabel: 'Open courses',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AdminCoursesScreen(session: widget.session),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlStat {
  final String label;
  final int? value;

  const _ControlStat({required this.label, required this.value});
}

class _ControlCenterCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final List<_ControlStat> stats;
  final String actionLabel;
  final VoidCallback onTap;

  const _ControlCenterCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.stats,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.18),
                          color.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: color.withValues(alpha: 0.14)),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.muted,
                            height: 1.32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: stats
                    .map((stat) => _ControlStatChip(stat: stat, color: color))
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlStatChip extends StatelessWidget {
  final _ControlStat stat;
  final Color color;

  const _ControlStatChip({required this.stat, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.value == null ? '...' : '${stat.value}',
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 5),
          Text(
            stat.label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _DashboardSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dashboard_customize_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _NavGrid extends StatelessWidget {
  final List<Widget> children;

  const _NavGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final width = columns == 2
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((child) => SizedBox(width: width, child: child))
              .toList(growable: false),
        );
      },
    );
  }
}

// ─── Navigation tile ─────────────────────────────────────────────────────────

class _CourseActivityPanel extends StatefulWidget {
  final AuthSession session;

  const _CourseActivityPanel({required this.session});

  @override
  State<_CourseActivityPanel> createState() => _CourseActivityPanelState();
}

class _CourseActivityPanelState extends State<_CourseActivityPanel> {
  final courseIdController = TextEditingController();
  Future<CourseActivitySummary>? summaryFuture;
  String loadedCourseId = '';
  String loadedCourseName = '';
  String? statusMessage;

  @override
  void dispose() {
    courseIdController.dispose();
    super.dispose();
  }

  void _loadSummary() {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) {
      setState(() {
        loadedCourseId = '';
        loadedCourseName = '';
        summaryFuture = null;
        statusMessage = 'Enter a course ID to search.';
      });
      return;
    }

    final matchingCourses = widget.session.courses.where(
      (course) => course.id.toLowerCase() == courseId.toLowerCase(),
    );
    final matchedCourse = matchingCourses.isEmpty
        ? null
        : matchingCourses.first;
    final hasAccess =
        widget.session.appUser.canViewAllCourses || matchedCourse != null;
    if (!hasAccess) {
      setState(() {
        loadedCourseId = courseId;
        loadedCourseName = '';
        summaryFuture = null;
        statusMessage =
            'Course $courseId is not available in this admin session.';
      });
      return;
    }

    setState(() {
      loadedCourseId = courseId;
      loadedCourseName = matchedCourse?.name ?? '';
      statusMessage = null;
      summaryFuture = FirestoreChatService.getCourseActivitySummary(
        courseId: courseId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CourseActivitySummary>(
      future: summaryFuture,
      builder: (context, snapshot) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Course activity summary',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Search by course ID to load only that course.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: courseIdController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Course ID',
                          hintText: 'Example: 2329',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onSubmitted: (_) => _loadSummary(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed:
                          snapshot.connectionState == ConnectionState.waiting
                          ? null
                          : _loadSummary,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Search'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (statusMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Text(
                      statusMessage!,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else if (summaryFuture == null)
                  const _InlineState(
                    icon: Icons.manage_search_rounded,
                    message:
                        'No course loaded. Enter its ID above when you need a summary.',
                    color: AppColors.primary,
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const PolishedLoadingCard(
                    title: 'Loading course activity',
                    message: 'Counting recent messages, uploads, and media.',
                  )
                else if (snapshot.hasError)
                  _InlineState(
                    icon: Icons.error_outline_rounded,
                    message:
                        'Could not load course $loadedCourseId: ${snapshot.error}',
                    color: AppColors.danger,
                  )
                else ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loadedCourseName.isEmpty
                              ? 'Course $loadedCourseId'
                              : '$loadedCourseName  -  $loadedCourseId',
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CourseSummaryGrid(summary: snapshot.data!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InlineState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;

  const _InlineState({
    required this.icon,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseSummaryGrid extends StatelessWidget {
  final CourseActivitySummary summary;

  const _CourseSummaryGrid({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _MiniStat(
          label: 'Messages',
          value: summary.messages,
          icon: Icons.chat_bubble_rounded,
          color: AppColors.primary,
        ),
        _MiniStat(
          label: 'Uploads',
          value: summary.uploads,
          icon: Icons.cloud_upload_rounded,
          color: AppColors.accent,
        ),
        _MiniStat(
          label: 'Images',
          value: summary.images,
          icon: Icons.image_rounded,
          color: AppColors.student,
        ),
        _MiniStat(
          label: 'Videos',
          value: summary.videos,
          icon: Icons.videocam_rounded,
          color: AppColors.admin,
        ),
        _MiniStat(
          label: 'Docs',
          value: summary.documents,
          icon: Icons.description_rounded,
          color: const Color(0xFF6A3DE8),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 124,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final Stream<int>? unreadStream;

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.unreadStream,
  });

  @override
  Widget build(BuildContext context) {
    final tile = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.14),
                        color.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.12)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: color.withValues(alpha: 0.72),
                        size: 22,
                      ),
                    ),
                    if (unreadStream != null)
                      Positioned(
                        right: -7,
                        top: -9,
                        child: StreamBuilder<int>(
                          stream: unreadStream,
                          builder: (context, snapshot) {
                            return UnreadBadge(
                              count: snapshot.data ?? 0,
                              compact: true,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return tile;
  }
}
