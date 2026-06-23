import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/admin_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';

class AdminUsersScreen extends StatefulWidget {
  final AuthSession session;

  const AdminUsersScreen({super.key, required this.session});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<AdminUser>? _users;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await AdminApi().listUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Users',
      showLogout: false,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 52, color: AppColors.danger),
              const SizedBox(height: 14),
              const Text(
                'Could not load users',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final users = _users ?? [];
    final students = users.where((u) => u.role == 'student').toList();
    final teachers = users.where((u) => u.role == 'teacher').toList();
    final admins = users.where((u) => u.role == 'admin').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ScreenHeader(
          title: 'All Users',
          subtitle: '${users.length} registered user${users.length == 1 ? '' : 's'}',
          icon: Icons.people_rounded,
        ),
        const SizedBox(height: 18),
        if (users.isEmpty)
          const _EmptyState()
        else ...[
          if (admins.isNotEmpty) ...[
            _SectionTitle(
              label: 'Admins',
              count: admins.length,
              color: AppColors.admin,
            ),
            const SizedBox(height: 8),
            ...admins.map((u) => _UserTile(user: u)),
            const SizedBox(height: 18),
          ],
          if (teachers.isNotEmpty) ...[
            _SectionTitle(
              label: 'Teachers',
              count: teachers.length,
              color: AppColors.teacher,
            ),
            const SizedBox(height: 8),
            ...teachers.map((u) => _UserTile(user: u)),
            const SizedBox(height: 18),
          ],
          if (students.isNotEmpty) ...[
            _SectionTitle(
              label: 'Students',
              count: students.length,
              color: AppColors.student,
            ),
            const SizedBox(height: 8),
            ...students.map((u) => _UserTile(user: u)),
          ],
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionTitle({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$label ($count)',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  final AdminUser user;

  const _UserTile({required this.user});

  Color get _roleColor {
    switch (user.role) {
      case 'teacher':
        return AppColors.teacher;
      case 'admin':
        return AppColors.admin;
      default:
        return AppColors.student;
    }
  }

  IconData get _roleIcon {
    switch (user.role) {
      case 'teacher':
        return Icons.menu_book_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: _roleColor.withValues(alpha: 0.12),
          child: Icon(_roleIcon, color: _roleColor, size: 20),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        subtitle: Text(
          user.email ?? user.lmsUserId,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _StatusBadge(status: user.status),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.success : AppColors.muted)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: isActive ? AppColors.success : AppColors.muted,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(top: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 52, color: AppColors.muted),
            SizedBox(height: 14),
            Text(
              'No users yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Users will appear here once students and teachers log in.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
