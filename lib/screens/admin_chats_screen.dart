import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';
import 'chat_screen.dart';

/// A flat thread entry combining course + thread metadata.
class _FlatThread {
  final String courseId;
  final String courseName;
  final String threadId;
  final String studentName;
  final String lastMessage;
  final String lastSenderName;
  final String lastSenderRole;
  final DateTime? updatedAt;

  const _FlatThread({
    required this.courseId,
    required this.courseName,
    required this.threadId,
    required this.studentName,
    required this.lastMessage,
    required this.lastSenderName,
    required this.lastSenderRole,
    this.updatedAt,
  });
}

class AdminChatsScreen extends StatefulWidget {
  final AuthSession session;

  const AdminChatsScreen({super.key, required this.session});

  @override
  State<AdminChatsScreen> createState() => _AdminChatsScreenState();
}

class _AdminChatsScreenState extends State<AdminChatsScreen> {
  List<_FlatThread>? _threads;
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
      final db = FirebaseFirestore.instance;
      final coursesSnap = await db.collection('courses').get();

      final List<_FlatThread> all = [];

      for (final courseDoc in coursesSnap.docs) {
        final courseId = courseDoc.id;
        final courseData = courseDoc.data();
        final courseName = courseData['name'] as String? ?? courseId;

        final threadsSnap = await db
            .collection('courses')
            .doc(courseId)
            .collection('threads')
            .orderBy('updated_at', descending: true)
            .get();

        for (final threadDoc in threadsSnap.docs) {
          final d = threadDoc.data();
          all.add(_FlatThread(
            courseId: courseId,
            courseName: courseName,
            threadId: threadDoc.id,
            studentName: d['student_name'] as String? ?? threadDoc.id,
            lastMessage: d['last_message'] as String? ?? '',
            lastSenderName: d['last_sender_name'] as String? ?? '',
            lastSenderRole: d['last_sender_role'] as String? ?? '',
            updatedAt: (d['updated_at'] as Timestamp?)?.toDate(),
          ));
        }
      }

      // Sort all threads by most recent first
      all.sort((a, b) {
        if (a.updatedAt == null && b.updatedAt == null) return 0;
        if (a.updatedAt == null) return 1;
        if (b.updatedAt == null) return -1;
        return b.updatedAt!.compareTo(a.updatedAt!);
      });

      if (mounted) {
        setState(() {
          _threads = all;
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
      title: 'Chat Monitor',
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
              const Icon(
                Icons.error_outline,
                size: 52,
                color: AppColors.danger,
              ),
              const SizedBox(height: 14),
              const Text(
                'Could not load chats',
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

    final threads = _threads ?? [];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Chat Monitor',
            subtitle: threads.isEmpty
                ? 'No active chat threads found.'
                : '${threads.length} thread${threads.length == 1 ? '' : 's'} across all courses — pull to refresh.',
            icon: Icons.forum_rounded,
          ),
          const SizedBox(height: 18),
          if (threads.isEmpty)
            const _EmptyState()
          else
            ...threads.map((t) => _ThreadTile(
                  thread: t,
                  session: widget.session,
                )),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final _FlatThread thread;
  final AuthSession session;

  const _ThreadTile({required this.thread, required this.session});

  Color get _roleColor {
    switch (thread.lastSenderRole) {
      case 'teacher':
        return AppColors.teacher;
      case 'admin':
        return AppColors.admin;
      default:
        return AppColors.student;
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeLabel =
        thread.updatedAt != null ? formatThreadTime(thread.updatedAt!) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Text(
            thread.studentName.isNotEmpty
                ? thread.studentName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                thread.studentName,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                thread.courseName,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: thread.lastMessage.isEmpty
            ? const Text(
                'No messages yet',
                style: TextStyle(
                  color: AppColors.muted,
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                ),
              )
            : RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  children: [
                    TextSpan(
                      text: '${thread.lastSenderName}: ',
                      style: TextStyle(
                        color: _roleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: thread.lastMessage),
                  ],
                ),
              ),
        trailing: Text(
          timeLabel,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              title: thread.studentName,
              currentUserRole: 'admin',
              courseId: thread.courseId,
              threadId: thread.threadId,
              senderName: session.appUser.name,
              threadStudentName: thread.studentName,
            ),
          ),
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
            Icon(Icons.forum_outlined, size: 52, color: AppColors.muted),
            SizedBox(height: 14),
            Text(
              'No threads yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'All chat threads across every course will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
