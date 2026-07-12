import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/admin_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';
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
    return AppScaffold(title: 'Users', showLogout: false, body: _buildBody());
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: PolishedLoadingCard(
          title: 'Loading users',
          message: 'Collecting registered students, teachers, and admins.',
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PolishedStateCard(
          icon: Icons.error_outline_rounded,
          title: 'Could not load users',
          message: _error!,
          color: AppColors.danger,
          actionLabel: 'Retry',
          onAction: _load,
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
          subtitle:
              '${users.length} registered user${users.length == 1 ? '' : 's'}',
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _roleColor.withValues(alpha: 0.14),
                      _roleColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _roleColor.withValues(alpha: 0.16)),
                ),
                child: Icon(_roleIcon, color: _roleColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? user.lmsUserId,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusBadge(status: user.status),
            ],
          ),
        ),
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
        color: (isActive ? AppColors.success : AppColors.muted).withValues(
          alpha: 0.12,
        ),
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
    return const PolishedStateCard(
      icon: Icons.people_outline_rounded,
      title: 'No users yet',
      message: 'Users will appear here once students and teachers log in.',
      color: AppColors.primary,
    );
  }
}
