import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/admin_api.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
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
import 'admin_users_screen.dart';

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
          if (!session.appUser.isManagerOperation) ...[
            _CourseActivityPanel(session: session),
            const SizedBox(height: 24),
          ],
          _AttentionNeededSection(insights: insights),
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

class _AttentionNeededSection extends StatelessWidget {
  final _DashboardInsights insights;

  const _AttentionNeededSection({required this.insights});

  @override
  Widget build(BuildContext context) {
    final items = [
      _AttentionItem(
        icon: Icons.person_search_rounded,
        title: 'Courses missing teacher',
        count: insights.missingTeachers,
        helper: 'Teacher name should appear in every course chat.',
        color: AppColors.teacher,
      ),
      _AttentionItem(
        icon: Icons.admin_panel_settings_rounded,
        title: 'Courses missing contact person',
        count: insights.missingContactPeople,
        helper: 'Contact-person mapping controls scoped admin access.',
        color: AppColors.admin,
      ),
      _AttentionItem(
        icon: Icons.group_off_rounded,
        title: 'Courses with no students',
        count: insights.emptyRosters,
        helper: 'Empty rosters may mean LMS sync or course setup needs review.',
        color: AppColors.danger,
      ),
      _AttentionItem(
        icon: Icons.label_off_rounded,
        title: 'Generic course names',
        count: insights.genericCourseNames,
        helper: 'Clear course names make search and reports easier.',
        color: const Color(0xFF6A3DE8),
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
                        (item) =>
                            SizedBox(width: width, child: _AttentionCard(item)),
                      )
                      .toList(growable: false),
                );
              },
            ),
    );
  }
}

class _AttentionItem {
  final IconData icon;
  final String title;
  final int count;
  final String helper;
  final Color color;

  const _AttentionItem({
    required this.icon,
    required this.title,
    required this.count,
    required this.helper,
    required this.color,
  });
}

class _AttentionCard extends StatelessWidget {
  final _AttentionItem item;

  const _AttentionCard(this.item);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.helper,
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
                color: item.color,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
