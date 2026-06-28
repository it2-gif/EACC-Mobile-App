import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import 'chat_screen.dart';

class StudentCourseChatsScreen extends StatelessWidget {
  final AuthSession session;
  final Course course;

  const StudentCourseChatsScreen({
    super.key,
    required this.session,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    final studentThreadId = session.lmsUser.lmsUserId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(course.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              'Course ${course.id}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _AnnouncementChatTile(course: course, session: session),
                const SizedBox(height: 12),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirestoreChatService.getThread(
                    courseId: course.id,
                    threadId: studentThreadId,
                  ),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    final unread =
                        (data?['student_unread_count'] as num?)?.toInt() ?? 0;
                    final lastMessage =
                        data?['last_message']?.toString() ??
                        'Private chat with your teacher';
                    final lastTime = formatThreadTime(
                      data?['last_message_at'] ?? data?['updated_at'],
                    );

                    return _ChatChoiceCard(
                      title: 'Private teacher chat',
                      subtitle: lastMessage,
                      time: lastTime,
                      icon: Icons.person_rounded,
                      color: AppColors.primary,
                      badge: unread > 0 ? '$unread' : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            title: course.teacherName ?? course.name,
                            currentUserRole: 'student',
                            courseId: course.id,
                            threadId: studentThreadId,
                            senderName: session.appUser.name,
                            threadStudentName: session.appUser.name,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnouncementChatTile extends StatelessWidget {
  final Course course;
  final AuthSession session;

  const _AnnouncementChatTile({required this.course, required this.session});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreChatService.getAnnouncementThread(courseId: course.id),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final lastMessage =
            data?['last_message']?.toString() ?? 'Course announcements';
        final lastTime = formatThreadTime(
          data?['last_message_at'] ?? data?['updated_at'],
        );

        return _ChatChoiceCard(
          title: 'Announcement chat',
          subtitle: lastMessage,
          time: lastTime,
          icon: Icons.campaign_rounded,
          color: AppColors.admin,
          pinned: true,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                title: 'Announcement chat',
                currentUserRole: 'student',
                courseId: course.id,
                threadId: FirestoreChatService.announcementThreadId,
                senderName: session.appUser.name,
                threadStudentName: session.appUser.name,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool pinned;
  final String? badge;

  const _ChatChoiceCard({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.icon,
    required this.color,
    required this.onTap,
    this.pinned = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (pinned)
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: AppColors.admin,
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
