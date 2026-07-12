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
    final keyPersonThreadId = FirestoreChatService.keyPersonStudentThreadId(
      studentThreadId,
    );
    final teacherDisplayName = _teacherDisplayName(course);
    final keyPersonName = course.keyPersonName?.trim();
    final keyPersonDisplayName =
        keyPersonName != null && keyPersonName.isNotEmpty
        ? keyPersonName
        : 'Contact person';
    final hasKeyPersonChat =
        (keyPersonName != null && keyPersonName.isNotEmpty) ||
        (course.keyPersonLmsUserId?.trim().isNotEmpty ?? false);

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
            if (keyPersonName != null && keyPersonName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Contact person: $keyPersonName',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
                _CourseChatHeader(
                  courseName: course.name,
                  courseId: course.id,
                  category: course.displayCategory,
                  teacherName: teacherDisplayName,
                  keyPersonName: keyPersonName,
                ),
                const SizedBox(height: 16),
                const _SectionLabel(
                  title: 'Course chats',
                  subtitle: 'Choose who you want to message for this course.',
                ),
                const SizedBox(height: 10),
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
                        'Chat directly with $teacherDisplayName';
                    final lastTime = formatThreadTime(
                      data?['last_message_at'] ?? data?['updated_at'],
                    );

                    return _ChatChoiceCard(
                      title: '$teacherDisplayName chat',
                      subtitle: lastMessage,
                      time: lastTime,
                      icon: Icons.support_agent_rounded,
                      color: AppColors.primary,
                      badge: unread > 0 ? '$unread' : null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            title: teacherDisplayName,
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
                if (hasKeyPersonChat) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirestoreChatService.getThread(
                      courseId: course.id,
                      threadId: keyPersonThreadId,
                    ),
                    builder: (context, snapshot) {
                      final data = snapshot.data?.data();
                      final unread =
                          (data?['student_unread_count'] as num?)?.toInt() ?? 0;
                      final lastMessage =
                          data?['last_message']?.toString() ??
                          'Chat directly with $keyPersonDisplayName';
                      final lastTime = formatThreadTime(
                        data?['last_message_at'] ?? data?['updated_at'],
                      );

                      return _ChatChoiceCard(
                        title: '$keyPersonDisplayName chat',
                        subtitle: lastMessage,
                        time: lastTime,
                        icon: Icons.verified_user_rounded,
                        color: AppColors.admin,
                        badge: unread > 0 ? '$unread' : null,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              title: keyPersonDisplayName,
                              currentUserRole: 'student',
                              courseId: course.id,
                              threadId: keyPersonThreadId,
                              senderName: session.appUser.name,
                              threadStudentName: session.appUser.name,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _teacherDisplayName(Course course) {
  final name = course.teacherName?.trim();
  if (name != null && name.isNotEmpty) return name;
  return 'Teacher';
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
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.15),
                      color.withValues(alpha: 0.06),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.admin.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 13,
                                  color: AppColors.admin,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Pinned',
                                  style: TextStyle(
                                    color: AppColors.admin,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
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
                        border: Border.all(color: Colors.white, width: 2),
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
                  const SizedBox(height: 8),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.primaryDark,
                      size: 19,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseChatHeader extends StatelessWidget {
  final String courseName;
  final String courseId;
  final String? category;
  final String teacherName;
  final String? keyPersonName;

  const _CourseChatHeader({
    required this.courseName,
    required this.courseId,
    required this.category,
    required this.teacherName,
    required this.keyPersonName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF286FBE), AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(Icons.forum_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courseName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Course $courseId',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (category != null && category!.trim().isNotEmpty)
                _HeroChip(label: category!, icon: Icons.category_rounded),
              _HeroChip(label: teacherName, icon: Icons.menu_book_rounded),
              if (keyPersonName != null && keyPersonName!.trim().isNotEmpty)
                _HeroChip(
                  label: keyPersonName!,
                  icon: Icons.verified_user_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _HeroChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 12,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
