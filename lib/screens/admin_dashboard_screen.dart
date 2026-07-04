import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/auth_session_manager.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/action_feedback.dart';
import '../widgets/app_scaffold.dart';
import 'admin_analysis_screen.dart';
import 'admin_announcements_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_chats_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_moderation_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  final AuthSession session;

  const AdminDashboardScreen({super.key, required this.session});

  Future<void> _logout(BuildContext context) async {
    await AuthSessionManager().logout();
    await PushNotificationService.instance.deactivate();
    if (!context.mounted) return;
    await showActionConfirmation(
      context,
      title: 'Logged out successfully',
      message: 'Your EACC Connection session was closed.',
      icon: Icons.logout_rounded,
      color: AppColors.danger,
    );

    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'EACC Admin',
      showLogout: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Welcome header
          _WelcomeHeader(
            name: session.appUser.name,
            isSuperAdmin: session.appUser.isSuperAdmin,
          ),
          const SizedBox(height: 14),
          _AnalysisEntryButton(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminAnalysisScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Live stat cards
          _StatsRow(session: session),
          const SizedBox(height: 24),
          const _CourseActivityPanel(),
          const SizedBox(height: 24),

          // Navigation tiles
          const Text(
            'ADMIN TOOLS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.muted,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.menu_book_rounded,
            title: 'Courses',
            subtitle: 'Browse all courses and student threads',
            color: AppColors.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminCoursesScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.people_rounded,
            title: 'Users',
            subtitle: 'View all registered students and teachers',
            color: const Color(0xFF0E7C86),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminUsersScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.forum_rounded,
            title: 'Chat Monitor',
            subtitle: 'Monitor and join any active conversation',
            color: const Color(0xFF6A3DE8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminChatsScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.campaign_rounded,
            title: 'Announcements',
            subtitle: 'Send course announcements or private broadcasts',
            color: AppColors.admin,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminAnnouncementsScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.admin_panel_settings_rounded,
            title: 'Bulk Moderation',
            subtitle: session.appUser.isSuperAdmin
                ? 'Search and soft-delete selected messages'
                : 'Review recent messages with super-admin controls locked',
            color: AppColors.danger,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminModerationScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _NavTile(
            icon: Icons.history_edu_rounded,
            title: 'Audit Trail',
            subtitle: 'Review message edits, deletes, pins, and moderation',
            color: AppColors.primaryDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminAuditScreen(session: session),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Logout
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Logout'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: BorderSide(color: AppColors.danger.withValues(alpha: 0.55)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
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

  const _WelcomeHeader({required this.name, required this.isSuperAdmin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSuperAdmin
                      ? 'EACC Super Administrator'
                      : 'EACC Administrator',
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
                            : Icons.admin_panel_settings_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSuperAdmin
                            ? 'Full access enabled'
                            : 'Standard admin access',
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

class _AnalysisEntryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AnalysisEntryButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Application Analysis',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'View courses, users, chats, messages, and upload totals.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.menu_book_rounded,
            label: 'Courses',
            value: courseCount,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.chat_bubble_rounded,
            label: 'Threads',
            value: threadCount,
            color: const Color(0xFF6A3DE8),
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
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
  const _CourseActivityPanel();

  @override
  State<_CourseActivityPanel> createState() => _CourseActivityPanelState();
}

class _CourseActivityPanelState extends State<_CourseActivityPanel> {
  final courseIdController = TextEditingController();
  Future<CourseActivitySummary>? summaryFuture;
  String loadedCourseId = '';

  @override
  void dispose() {
    courseIdController.dispose();
    super.dispose();
  }

  void _loadSummary() {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) return;

    setState(() {
      loadedCourseId = courseId;
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
                            'Load one course to count recent messages and uploads.',
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
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: 'Course ID',
                          hintText: 'Enter course ID',
                          prefixIcon: Icon(Icons.filter_alt_rounded),
                        ),
                        onSubmitted: (_) => _loadSummary(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _loadSummary,
                      icon: const Icon(Icons.insights_rounded),
                      label: const Text('Show'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (summaryFuture == null)
                  const Text(
                    'No course loaded yet.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const LinearProgressIndicator(minHeight: 3)
                else if (snapshot.hasError)
                  Text(
                    'Could not load course $loadedCourseId: ${snapshot.error}',
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  _CourseSummaryGrid(summary: snapshot.data!),
              ],
            ),
          ),
        );
      },
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
    return Card(
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: color.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
