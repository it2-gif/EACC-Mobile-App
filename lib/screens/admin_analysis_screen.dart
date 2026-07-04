import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/admin_api.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';

class AdminAnalysisScreen extends StatefulWidget {
  final AuthSession session;

  const AdminAnalysisScreen({super.key, required this.session});

  @override
  State<AdminAnalysisScreen> createState() => _AdminAnalysisScreenState();
}

class _AdminAnalysisScreenState extends State<AdminAnalysisScreen> {
  late Future<_AnalysisData> analysisFuture;

  @override
  void initState() {
    super.initState();
    analysisFuture = _loadAnalysis();
  }

  Future<_AnalysisData> _loadAnalysis() async {
    List<AdminUser>? users;
    String? usersError;

    try {
      users = await AdminApi().listUsers();
    } catch (error) {
      usersError = error.toString();
    }

    final activity = await FirestoreChatService.getApplicationActivitySummary(
      courseIds: widget.session.courses.map((course) => course.id),
    );

    return _AnalysisData.fromSession(
      session: widget.session,
      activity: activity,
      users: users,
      usersError: usersError,
    );
  }

  void _refresh() {
    setState(() {
      analysisFuture = _loadAnalysis();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Analysis',
      showLogout: false,
      body: FutureBuilder<_AnalysisData>(
        future: analysisFuture,
        builder: (context, snapshot) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              ScreenHeader(
                title: 'Application analysis',
                subtitle:
                    'A clean overview of LMS users, courses, chats, messages, and uploads.',
                icon: Icons.analytics_rounded,
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting)
                const _AnalysisLoading()
              else if (snapshot.hasError)
                _AnalysisError(error: '${snapshot.error}', onRetry: _refresh)
              else
                _AnalysisContent(data: snapshot.data!, onRefresh: _refresh),
            ],
          );
        },
      ),
    );
  }
}

class _AnalysisData {
  final int courses;
  final int chats;
  final int students;
  final int teachers;
  final int admins;
  final int messages;
  final int uploads;
  final int images;
  final int videos;
  final int documents;
  final int voiceMessages;
  final int uploadedBytes;
  final String? usersError;

  const _AnalysisData({
    required this.courses,
    required this.chats,
    required this.students,
    required this.teachers,
    required this.admins,
    required this.messages,
    required this.uploads,
    required this.images,
    required this.videos,
    required this.documents,
    required this.voiceMessages,
    required this.uploadedBytes,
    this.usersError,
  });

  factory _AnalysisData.fromSession({
    required AuthSession session,
    required ApplicationActivitySummary activity,
    required List<AdminUser>? users,
    required String? usersError,
  }) {
    final uniqueStudents = <String>{};
    final uniqueTeachers = <String>{};

    for (final course in session.courses) {
      for (final student in course.students) {
        uniqueStudents.add(student.id);
      }

      final teacher = course.teacherName?.trim();
      if (teacher != null && teacher.isNotEmpty) {
        uniqueTeachers.add(teacher.toLowerCase());
      }
    }

    final students = users != null
        ? users.where((user) => user.role == 'student').length
        : uniqueStudents.length;
    final teachers = users != null
        ? users.where((user) => user.role == 'teacher').length
        : uniqueTeachers.length;
    final admins = users != null
        ? users.where((user) => user.role == 'admin').length
        : 1;

    return _AnalysisData(
      courses: session.courses.length,
      chats: activity.chats,
      students: students,
      teachers: teachers,
      admins: admins,
      messages: activity.messages,
      uploads: activity.uploads,
      images: activity.images,
      videos: activity.videos,
      documents: activity.documents,
      voiceMessages: activity.voiceMessages,
      uploadedBytes: activity.uploadedBytes,
      usersError: usersError,
    );
  }

  int get storageItems => uploads + voiceMessages;
}

class _AnalysisContent extends StatelessWidget {
  final _AnalysisData data;
  final VoidCallback onRefresh;

  const _AnalysisContent({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OverviewHero(data: data, onRefresh: onRefresh),
        const SizedBox(height: 14),
        if (data.usersError != null) ...[
          _WarningBanner(message: data.usersError!),
          const SizedBox(height: 14),
        ],
        _CostUsagePanel(data: data),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'LMS structure',
          subtitle: 'People and courses available to this admin session.',
        ),
        const SizedBox(height: 10),
        _MetricGrid(
          cards: [
            _MetricData(
              label: 'Courses',
              value: data.courses,
              icon: Icons.menu_book_rounded,
              color: AppColors.primary,
            ),
            _MetricData(
              label: 'Students',
              value: data.students,
              icon: Icons.school_rounded,
              color: AppColors.student,
            ),
            _MetricData(
              label: 'Teachers',
              value: data.teachers,
              icon: Icons.auto_stories_rounded,
              color: AppColors.teacher,
            ),
            _MetricData(
              label: 'Admins',
              value: data.admins,
              icon: Icons.admin_panel_settings_rounded,
              color: AppColors.admin,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'Communication',
          subtitle: 'Counts from Firestore, grouped by LMS course.',
        ),
        const SizedBox(height: 10),
        _MetricGrid(
          cards: [
            _MetricData(
              label: 'Chats',
              value: data.chats,
              icon: Icons.forum_rounded,
              color: const Color(0xFF6A3DE8),
            ),
            _MetricData(
              label: 'Messages',
              value: data.messages,
              icon: Icons.chat_bubble_rounded,
              color: AppColors.primary,
            ),
            _MetricData(
              label: 'Uploads',
              value: data.uploads,
              icon: Icons.cloud_upload_rounded,
              color: AppColors.accent,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'Upload breakdown',
          subtitle: 'Media and document usage across the loaded courses.',
        ),
        const SizedBox(height: 10),
        _MetricGrid(
          cards: [
            _MetricData(
              label: 'Images',
              value: data.images,
              icon: Icons.image_rounded,
              color: AppColors.student,
            ),
            _MetricData(
              label: 'Videos',
              value: data.videos,
              icon: Icons.videocam_rounded,
              color: AppColors.admin,
            ),
            _MetricData(
              label: 'Docs',
              value: data.documents,
              icon: Icons.description_rounded,
              color: const Color(0xFF6A3DE8),
            ),
            _MetricData(
              label: 'Voice',
              value: data.voiceMessages,
              icon: Icons.mic_rounded,
              color: AppColors.primaryDark,
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewHero extends StatelessWidget {
  final _AnalysisData data;
  final VoidCallback onRefresh;

  const _OverviewHero({required this.data, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.query_stats_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'EACC Connection overview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.courses} courses, ${data.chats} chats, ${data.messages} messages',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: 'Refresh analysis',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _CostUsagePanel extends StatelessWidget {
  static const int _firebaseStorageFreeBytes = 5 * 1024 * 1024 * 1024;
  static const int _firebaseUploadRequestsFreeMonthly = 5000;
  static const int _firestoreReadReferenceDaily = 50000;
  static const int _firestoreWriteReferenceDaily = 20000;

  final _AnalysisData data;

  const _CostUsagePanel({required this.data});

  @override
  Widget build(BuildContext context) {
    final storageRatio = _safeRatio(
      data.uploadedBytes,
      _firebaseStorageFreeBytes,
    );
    final uploadRatio = _safeRatio(
      data.storageItems,
      _firebaseUploadRequestsFreeMonthly,
    );
    final messageReadRatio = _safeRatio(
      data.messages,
      _firestoreReadReferenceDaily,
    );
    final messageWriteRatio = _safeRatio(
      data.messages,
      _firestoreWriteReferenceDaily,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.savings_rounded,
                    color: AppColors.success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cost and usage estimate',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Estimated from app data. Firebase and Railway remain the billing source of truth.',
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
            const SizedBox(height: 16),
            _UsageLimitRow(
              icon: Icons.storage_rounded,
              title: 'Firebase Storage',
              value: _formatBytes(data.uploadedBytes),
              limit: '5 GB free storage reference',
              ratio: storageRatio,
              color: AppColors.accent,
            ),
            const SizedBox(height: 12),
            _UsageLimitRow(
              icon: Icons.cloud_upload_rounded,
              title: 'Upload records',
              value: '${data.storageItems}',
              limit: '5K upload requests/month reference',
              ratio: uploadRatio,
              color: AppColors.student,
            ),
            const SizedBox(height: 12),
            _UsageLimitRow(
              icon: Icons.mark_chat_read_rounded,
              title: 'Message read volume',
              value: '${data.messages}',
              limit: '50K Firestore reads/day reference',
              ratio: messageReadRatio,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            _UsageLimitRow(
              icon: Icons.edit_note_rounded,
              title: 'Message write volume',
              value: '${data.messages}',
              limit: '20K Firestore writes/day reference',
              ratio: messageWriteRatio,
              color: const Color(0xFF6A3DE8),
            ),
            const SizedBox(height: 14),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CostChip(
                  icon: Icons.rocket_launch_rounded,
                  title: 'Railway backend',
                  value: 'USD 5/month',
                  note: 'Current hosting estimate',
                  color: AppColors.primary,
                ),
                _CostChip(
                  icon: Icons.local_fire_department_rounded,
                  title: 'Firebase',
                  value: 'Free tier',
                  note: 'Until usage passes free limits',
                  color: AppColors.admin,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.14),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.dns_rounded, color: AppColors.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Railway backend is the fixed hosted service. Your current planning estimate is the Railway hobby cost plus any Firebase overage after free limits.',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
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

class _CostChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String note;
  final Color color;

  const _CostChip({
    required this.icon,
    required this.title,
    required this.value,
    required this.note,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageLimitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String limit;
  final double ratio;
  final Color color;

  const _UsageLimitRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.limit,
    required this.ratio,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final status = _usageStatus(ratio);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      limit,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  _UsageStatusChip(status: status),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: color.withValues(alpha: 0.11),
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageStatusChip extends StatelessWidget {
  final _UsageStatus status;

  const _UsageStatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: status.color.withValues(alpha: 0.18)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _UsageStatus {
  final String label;
  final Color color;

  const _UsageStatus({required this.label, required this.color});
}

class _MetricGrid extends StatelessWidget {
  final List<_MetricData> cards;

  const _MetricGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 620;
        final itemWidth = isWide
            ? (constraints.maxWidth - 20) / 3
            : (constraints.maxWidth - 10) / 2;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map(
                (card) => SizedBox(width: itemWidth, child: _MetricCard(card)),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _MetricData {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _MetricCard extends StatelessWidget {
  final _MetricData data;

  const _MetricCard(this.data);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, color: data.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${data.value}',
                    style: TextStyle(
                      color: data.color,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    data.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
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
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 15,
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
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;

  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.admin.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.admin.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.admin),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'User counts used the LMS session fallback. Backend users could not load: $message',
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double _safeRatio(int value, int limit) {
  if (limit <= 0) return 0;
  return (value / limit).clamp(0.0, 1.0);
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';

  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;

  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }

  final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

_UsageStatus _usageStatus(double ratio) {
  if (ratio >= 0.9) {
    return const _UsageStatus(label: 'High', color: AppColors.danger);
  }

  if (ratio >= 0.7) {
    return const _UsageStatus(label: 'Watch', color: AppColors.admin);
  }

  return const _UsageStatus(label: 'Healthy', color: AppColors.success);
}

class _AnalysisLoading extends StatelessWidget {
  const _AnalysisLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            LinearProgressIndicator(minHeight: 3),
            SizedBox(height: 16),
            Text(
              'Loading application analysis...',
              style: TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisError extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _AnalysisError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.danger,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
