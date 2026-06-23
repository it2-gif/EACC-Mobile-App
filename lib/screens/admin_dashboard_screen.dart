import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import 'admin_chats_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  final AuthSession session;

  const AdminDashboardScreen({super.key, required this.session});

  void _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
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
          _WelcomeHeader(name: session.appUser.name),
          const SizedBox(height: 20),

          // Live stat cards
          _StatsRow(),
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
          const SizedBox(height: 24),

          // Logout
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

// ─── Welcome header ─────────────────────────────────────────────────────────

class _WelcomeHeader extends StatelessWidget {
  final String name;

  const _WelcomeHeader({required this.name});

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
                const Text(
                  'EACC Administrator',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
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
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    Stream<QuerySnapshot<Map<String, dynamic>>>? coursesStream;
    try {
      coursesStream = FirebaseFirestore.instance.collection('courses').snapshots();
    } catch (_) {
      // Firebase not initialized (test environment).
    }

    if (coursesStream == null) {
      return Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.menu_book_rounded,
              label: 'Courses',
              value: 0,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.chat_bubble_rounded,
              label: 'Threads',
              value: 0,
              color: const Color(0xFF6A3DE8),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: coursesStream,
      builder: (context, coursesSnapshot) {
        final courseCount = coursesSnapshot.data?.docs.length ?? 0;

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
              child: _ThreadCountCard(courseIds: coursesSnapshot.data?.docs.map((d) => d.id).toList() ?? []),
            ),
          ],
        );
      },
    );
  }
}

class _ThreadCountCard extends StatelessWidget {
  final List<String> courseIds;

  const _ThreadCountCard({required this.courseIds});

  @override
  Widget build(BuildContext context) {
    if (courseIds.isEmpty) {
      return const _StatCard(
        icon: Icons.chat_bubble_rounded,
        label: 'Threads',
        value: 0,
        color: Color(0xFF6A3DE8),
      );
    }

    return StreamBuilder<int>(
      stream: _countAllThreads(courseIds),
      builder: (context, snap) {
        return _StatCard(
          icon: Icons.chat_bubble_rounded,
          label: 'Threads',
          value: snap.data ?? 0,
          color: const Color(0xFF6A3DE8),
        );
      },
    );
  }

  Stream<int> _countAllThreads(List<String> courseIds) async* {
    final db = FirebaseFirestore.instance;

    // Emit total thread count by listening to the first course, then accumulate
    // (simplified: just emit a count from all thread collections)
    int total = 0;
    for (final id in courseIds) {
      final snap = await db.collection('courses').doc(id).collection('threads').get();
      total += snap.docs.length;
    }
    yield total;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
