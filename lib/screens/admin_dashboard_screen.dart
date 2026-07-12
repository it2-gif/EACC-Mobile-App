import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/support_entry_card.dart';
import 'admin_analysis_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_users_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  final AuthSession session;

  const AdminDashboardScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final canSeeAnalysis =
        session.appUser.isSuperAdmin || session.appUser.isTechnicalSupport;
    final toolTiles = <Widget>[
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
      _NavTile(
        icon: Icons.menu_book_rounded,
        title: 'Courses',
        subtitle: session.appUser.canViewAllCourses
            ? 'Search courses and open student chats'
            : 'Open your linked courses and student chats',
        color: AppColors.primary,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdminCoursesScreen(session: session),
          ),
        ),
      ),
      if (session.appUser.isSuperAdmin)
        _NavTile(
          icon: Icons.people_rounded,
          title: 'Users',
          subtitle: 'Review registered students, teachers, and admins',
          color: const Color(0xFF0E7C86),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminUsersScreen(session: session),
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
          _StatsRow(session: session),
          const SizedBox(height: 24),
          if (!session.appUser.isManagerOperation) ...[
            _CourseActivityPanel(session: session),
            const SizedBox(height: 24),
          ],

          _DashboardSection(
            title: session.appUser.isSuperAdmin
                ? 'Admin tools'
                : 'Course tools',
            subtitle: session.appUser.isSuperAdmin
                ? 'Manage courses, communication, moderation, and reports.'
                : 'Open the course tools available to your account.',
            child: _NavGrid(children: toolTiles),
          ),
        ],
      ),
    );
  }
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

class _StatsRow extends StatelessWidget {
  final AuthSession session;

  const _StatsRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final courseCount = session.courses.length;
    final threadCount = session.courses.fold<int>(
      0,
      (total, course) => total + course.students.length,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                icon: Icons.menu_book_rounded,
                label: 'Courses',
                value: courseCount,
                color: AppColors.primary,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _StatCard(
                icon: Icons.chat_bubble_rounded,
                label: 'Chats',
                value: threadCount,
                color: const Color(0xFF6A3DE8),
              ),
            ),
          ],
        );
      },
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
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

  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
