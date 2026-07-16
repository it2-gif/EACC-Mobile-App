import 'dart:async';

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
  static const _pageSize = 10;

  final _api = AdminApi();
  final _searchController = TextEditingController();
  final List<AdminUser> _users = [];
  AdminUsersCounts _counts = const AdminUsersCounts.empty();
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _total = 0;
  int _requestSerial = 0;
  Timer? _searchDebounce;
  String _query = '';
  String _roleFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = true}) async {
    final requestId = ++_requestSerial;
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
      _error = null;
    });

    try {
      final page = await _api.listUsers(
        skip: reset ? 0 : _users.length,
        take: _pageSize,
        role: _roleFilter == 'all' ? null : _roleFilter,
        query: _query,
      );
      if (mounted) {
        if (requestId != _requestSerial) return;
        setState(() {
          if (reset) {
            _users
              ..clear()
              ..addAll(page.items);
          } else {
            _users.addAll(page.items);
          }
          _counts = page.counts;
          _total = page.total;
          _hasMore = page.hasMore;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        if (requestId != _requestSerial) return;
        setState(() {
          _error = e.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  void _onRoleChanged(String role) {
    if (role == _roleFilter) return;
    setState(() => _roleFilter = role);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'People Dashboard',
      showLogout: false,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: PolishedLoadingCard(
          title: 'Loading users',
          message: 'Collecting registered students, teachers, and admins.',
        ),
      );
    }

    if (_error != null && _users.isEmpty) {
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

    final users = List<AdminUser>.unmodifiable(_users);
    final students = users.where((u) => u.role == 'student').toList();
    final teachers = users.where((u) => u.role == 'teacher').toList();
    final admins = users.where((u) => u.role == 'admin').toList();
    final hasFilters = _query.trim().isNotEmpty || _roleFilter != 'all';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ScreenHeader(
          title: 'People Dashboard',
          subtitle: _total == 0
              ? 'Search registered students, teachers, and admins.'
              : 'Showing ${users.length} of $_total matching people.',
          icon: Icons.people_rounded,
        ),
        const SizedBox(height: 18),
        _PeopleStats(counts: _counts),
        const SizedBox(height: 12),
        _PeopleSearchBar(
          controller: _searchController,
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 12),
        _RoleFilterBar(
          selectedRole: _roleFilter,
          counts: _counts,
          onChanged: _onRoleChanged,
        ),
        const SizedBox(height: 18),
        if (users.isEmpty && !hasFilters)
          const _EmptyState()
        else if (users.isEmpty)
          _NoPeopleResults(query: _query, role: _roleFilter)
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
          const SizedBox(height: 8),
          _LoadMorePeopleCard(
            loaded: users.length,
            total: _total,
            hasMore: _hasMore,
            loading: _loadingMore,
            error: _error,
            onLoadMore: () => _load(reset: false),
          ),
        ],
      ],
    );
  }
}

class _PeopleStats extends StatelessWidget {
  final AdminUsersCounts counts;

  const _PeopleStats({required this.counts});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: itemWidth,
              child: _PeopleStatCard(
                label: 'Admins',
                value: counts.admins,
                icon: Icons.admin_panel_settings_rounded,
                color: AppColors.admin,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _PeopleStatCard(
                label: 'Teachers',
                value: counts.teachers,
                icon: Icons.menu_book_rounded,
                color: AppColors.teacher,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: _PeopleStatCard(
                label: 'Students',
                value: counts.students,
                icon: Icons.school_rounded,
                color: AppColors.student,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PeopleStatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _PeopleStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

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
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 21),
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
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.muted,
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

class _PeopleSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _PeopleSearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Search people',
            hintText: 'Name, LMS ID, email, or role',
            prefixIcon: Icon(Icons.manage_search_rounded),
          ),
        ),
      ),
    );
  }
}

class _RoleFilterBar extends StatelessWidget {
  final String selectedRole;
  final AdminUsersCounts counts;
  final ValueChanged<String> onChanged;

  const _RoleFilterBar({
    required this.selectedRole,
    required this.counts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final roles = [
      _RoleFilter('all', 'All', counts.all, AppColors.primary),
      _RoleFilter('admin', 'Admins', counts.admins, AppColors.admin),
      _RoleFilter('teacher', 'Teachers', counts.teachers, AppColors.teacher),
      _RoleFilter('student', 'Students', counts.students, AppColors.student),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: roles
          .map((role) {
            final selected = role.value == selectedRole;
            return ChoiceChip(
              selected: selected,
              label: Text('${role.label} (${role.count})'),
              avatar: Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: selected ? role.color : AppColors.muted,
              ),
              labelStyle: TextStyle(
                color: selected ? role.color : AppColors.muted,
                fontWeight: FontWeight.w800,
              ),
              selectedColor: role.color.withValues(alpha: 0.12),
              side: BorderSide(
                color: selected
                    ? role.color.withValues(alpha: 0.35)
                    : AppColors.border,
              ),
              onSelected: (_) => onChanged(role.value),
            );
          })
          .toList(growable: false),
    );
  }
}

class _RoleFilter {
  final String value;
  final String label;
  final int count;
  final Color color;

  const _RoleFilter(this.value, this.label, this.count, this.color);
}

class _NoPeopleResults extends StatelessWidget {
  final String query;
  final String role;

  const _NoPeopleResults({required this.query, required this.role});

  @override
  Widget build(BuildContext context) {
    final roleLabel = role == 'all' ? 'people' : role;
    final trimmedQuery = query.trim();

    return PolishedStateCard(
      icon: Icons.manage_search_rounded,
      title: 'No matching $roleLabel',
      message: trimmedQuery.isEmpty
          ? 'Try another role filter to narrow the dashboard.'
          : 'No users match "$trimmedQuery". Try a name, LMS ID, email, or role.',
      color: AppColors.primary,
    );
  }
}

class _LoadMorePeopleCard extends StatelessWidget {
  final int loaded;
  final int total;
  final bool hasMore;
  final bool loading;
  final String? error;
  final VoidCallback onLoadMore;

  const _LoadMorePeopleCard({
    required this.loaded,
    required this.total,
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && error!.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                hasMore ? Icons.playlist_add_rounded : Icons.done_all_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasError
                    ? error!
                    : hasMore
                    ? 'Loaded $loaded of $total people.'
                    : 'All $total matching people are loaded.',
                style: TextStyle(
                  color: hasError ? AppColors.danger : AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (hasMore || hasError) ...[
              const SizedBox(width: 10),
              FilledButton(
                onPressed: loading ? null : onLoadMore,
                child: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load 10 more'),
              ),
            ],
          ],
        ),
      ),
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
