import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/firestore_chat_service.dart';
import '../services/notification_api.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/screen_header.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  final AuthSession session;

  const AdminAnnouncementsScreen({super.key, required this.session});

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  static final NotificationApi _notificationApi = NotificationApi();

  final courseMessageController = TextEditingController();
  final privateMessageController = TextEditingController();
  final selectedCourseIds = <String>{};
  final selectedStudentKeys = <String>{};
  bool sendingCourseAnnouncement = false;
  bool sendingPrivateBroadcast = false;

  List<Course> get courses => widget.session.courses;

  List<_StudentTarget> get studentTargets {
    final targets = <_StudentTarget>[];
    for (final course in courses) {
      for (final student in course.students) {
        targets.add(
          _StudentTarget(
            courseId: course.id,
            courseName: course.name,
            studentId: student.id,
            studentName: student.name,
          ),
        );
      }
    }
    targets.sort((a, b) {
      final courseCompare = a.courseName.toLowerCase().compareTo(
        b.courseName.toLowerCase(),
      );
      if (courseCompare != 0) return courseCompare;
      return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
    });
    return targets;
  }

  @override
  void initState() {
    super.initState();
    selectedCourseIds.addAll(courses.map((course) => course.id));
  }

  @override
  void dispose() {
    courseMessageController.dispose();
    privateMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Announcements',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const ScreenHeader(
            title: 'Announcements',
            subtitle: 'Send course updates or targeted private broadcasts.',
            icon: Icons.campaign_rounded,
          ),
          const SizedBox(height: 18),
          _CourseAnnouncementPanel(
            courses: courses,
            controller: courseMessageController,
            selectedCourseIds: selectedCourseIds,
            isSending: sendingCourseAnnouncement,
            onChanged: () => setState(() {}),
            onSend: sendCourseAnnouncements,
          ),
          const SizedBox(height: 16),
          _PrivateBroadcastPanel(
            targets: studentTargets,
            controller: privateMessageController,
            selectedStudentKeys: selectedStudentKeys,
            isSending: sendingPrivateBroadcast,
            onChanged: () => setState(() {}),
            onSend: sendPrivateBroadcasts,
          ),
        ],
      ),
    );
  }

  Future<void> sendCourseAnnouncements() async {
    final text = courseMessageController.text.trim();
    if (text.isEmpty ||
        selectedCourseIds.isEmpty ||
        sendingCourseAnnouncement) {
      return;
    }

    setState(() => sendingCourseAnnouncement = true);
    try {
      final selectedCourses = courses.where(
        (course) => selectedCourseIds.contains(course.id),
      );
      for (final course in selectedCourses) {
        await FirestoreChatService.sendTextMessage(
          courseId: course.id,
          threadId: FirestoreChatService.announcementThreadId,
          senderName: widget.session.appUser.name,
          senderRole: 'admin',
          text: text,
        );
        await _notificationApi.notifyChatMessage(
          courseId: course.id,
          threadId: FirestoreChatService.announcementThreadId,
          senderRole: 'admin',
          senderName: widget.session.appUser.name,
          messageType: 'text',
          previewText: text,
          audience: 'course',
        );
      }

      courseMessageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Announcement sent to ${selectedCourseIds.length} course${selectedCourseIds.length == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Announcement failed: $error')));
      }
    } finally {
      if (mounted) setState(() => sendingCourseAnnouncement = false);
    }
  }

  Future<void> sendPrivateBroadcasts() async {
    final text = privateMessageController.text.trim();
    if (text.isEmpty ||
        selectedStudentKeys.isEmpty ||
        sendingPrivateBroadcast) {
      return;
    }

    setState(() => sendingPrivateBroadcast = true);
    try {
      final selectedTargets = studentTargets.where(
        (target) => selectedStudentKeys.contains(target.key),
      );
      var sentCount = 0;
      for (final target in selectedTargets) {
        await FirestoreChatService.sendTextMessage(
          courseId: target.courseId,
          threadId: target.studentId,
          senderName: widget.session.appUser.name,
          senderRole: 'admin',
          text: text,
          studentName: target.studentName,
        );
        await _notificationApi.notifyChatMessage(
          courseId: target.courseId,
          threadId: target.studentId,
          senderRole: 'admin',
          senderName: widget.session.appUser.name,
          messageType: 'text',
          previewText: text,
          studentName: target.studentName,
        );
        sentCount++;
      }

      privateMessageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Private broadcast sent to $sentCount student${sentCount == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Private broadcast failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => sendingPrivateBroadcast = false);
    }
  }
}

class _CourseAnnouncementPanel extends StatelessWidget {
  final List<Course> courses;
  final TextEditingController controller;
  final Set<String> selectedCourseIds;
  final bool isSending;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  const _CourseAnnouncementPanel({
    required this.courses,
    required this.controller,
    required this.selectedCourseIds,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.campaign_rounded,
              title: 'Course announcements',
              subtitle: 'Posts into the pinned announcement chat.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Write the announcement',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _SelectionToolbar(
              selected: selectedCourseIds.length,
              total: courses.length,
              onSelectAll: () {
                selectedCourseIds
                  ..clear()
                  ..addAll(courses.map((course) => course.id));
                onChanged();
              },
              onClear: () {
                selectedCourseIds.clear();
                onChanged();
              },
            ),
            ...courses.map(
              (course) => CheckboxListTile(
                value: selectedCourseIds.contains(course.id),
                dense: true,
                title: Text(course.name),
                subtitle: Text('Course ${course.id}'),
                onChanged: (value) {
                  if (value == true) {
                    selectedCourseIds.add(course.id);
                  } else {
                    selectedCourseIds.remove(course.id);
                  }
                  onChanged();
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Send announcement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivateBroadcastPanel extends StatelessWidget {
  final List<_StudentTarget> targets;
  final TextEditingController controller;
  final Set<String> selectedStudentKeys;
  final bool isSending;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  const _PrivateBroadcastPanel({
    required this.targets,
    required this.controller,
    required this.selectedStudentKeys,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.mark_email_unread_rounded,
              title: 'Private broadcast',
              subtitle: 'Sends the same message into selected private chats.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Write the private message',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _SelectionToolbar(
              selected: selectedStudentKeys.length,
              total: targets.length,
              onSelectAll: () {
                selectedStudentKeys
                  ..clear()
                  ..addAll(targets.map((target) => target.key));
                onChanged();
              },
              onClear: () {
                selectedStudentKeys.clear();
                onChanged();
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: targets.length,
                itemBuilder: (context, index) {
                  final target = targets[index];
                  final selected = selectedStudentKeys.contains(target.key);
                  return _StudentTargetSelectionTile(
                    name: target.studentName,
                    subtitle:
                        '${target.courseName} - Course ${target.courseId}',
                    selected: selected,
                    onTap: () {
                      if (selected) {
                        selectedStudentKeys.remove(target.key);
                      } else {
                        selectedStudentKeys.add(target.key);
                      }
                      onChanged();
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSending ? null : onSend,
                icon: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('Send private broadcast'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  final int selected;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const _SelectionToolbar({
    required this.selected,
    required this.total,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton(onPressed: onSelectAll, child: const Text('Select all')),
        TextButton(onPressed: onClear, child: const Text('Clear')),
        const Spacer(),
        Text(
          '$selected/$total selected',
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StudentTarget {
  final String courseId;
  final String courseName;
  final String studentId;
  final String studentName;

  const _StudentTarget({
    required this.courseId,
    required this.courseName,
    required this.studentId,
    required this.studentName,
  });

  String get key => '$courseId:$studentId';
}

class _StudentTargetSelectionTile extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StudentTargetSelectionTile({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.admin.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppColors.admin.withValues(alpha: 0.5)
                    : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.admin
                        : AppColors.student.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.student,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.admin : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? AppColors.admin : AppColors.border,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: Colors.white,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
