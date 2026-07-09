import 'package:cloud_firestore/cloud_firestore.dart';
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
  final courseFilterController = TextEditingController();
  final studentFilterController = TextEditingController();
  final selectedCourseIds = <String>{};
  final selectedStudentKeys = <String>{};
  String courseFilter = '';
  String studentFilter = '';
  DateTime? scheduledCourseAnnouncementAt;
  bool pinCourseAnnouncements = true;
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
            courseName: course.displayName,
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
  void dispose() {
    courseMessageController.dispose();
    privateMessageController.dispose();
    courseFilterController.dispose();
    studentFilterController.dispose();
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
            subtitle: 'Send course updates or direct messages to students.',
            icon: Icons.campaign_rounded,
          ),
          const SizedBox(height: 18),
          _CourseAnnouncementPanel(
            courses: courses,
            controller: courseMessageController,
            filterController: courseFilterController,
            filter: courseFilter,
            selectedCourseIds: selectedCourseIds,
            scheduledAt: scheduledCourseAnnouncementAt,
            pinAnnouncements: pinCourseAnnouncements,
            isSending: sendingCourseAnnouncement,
            onChanged: () => setState(() {}),
            onFilterChanged: (value) =>
                setState(() => courseFilter = value.trim().toLowerCase()),
            onClearFilter: () {
              courseFilterController.clear();
              setState(() => courseFilter = '');
            },
            onPickSchedule: pickCourseAnnouncementSchedule,
            onClearSchedule: () =>
                setState(() => scheduledCourseAnnouncementAt = null),
            onPinChanged: (value) =>
                setState(() => pinCourseAnnouncements = value),
            onUseTemplate: (template) {
              courseMessageController.text = template;
              courseMessageController.selection = TextSelection.collapsed(
                offset: courseMessageController.text.length,
              );
            },
            onSend: sendCourseAnnouncements,
          ),
          const SizedBox(height: 16),
          _PrivateBroadcastPanel(
            targets: studentTargets,
            controller: privateMessageController,
            filterController: studentFilterController,
            filter: studentFilter,
            selectedStudentKeys: selectedStudentKeys,
            isSending: sendingPrivateBroadcast,
            onChanged: () => setState(() {}),
            onFilterChanged: (value) =>
                setState(() => studentFilter = value.trim().toLowerCase()),
            onClearFilter: () {
              studentFilterController.clear();
              setState(() => studentFilter = '');
            },
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
      final scheduledAt = scheduledCourseAnnouncementAt;
      if (scheduledAt != null && scheduledAt.isAfter(DateTime.now())) {
        final selectedIds = Set<String>.from(selectedCourseIds);
        final scheduledText = text;
        final shouldPin = pinCourseAnnouncements;
        final delay = scheduledAt.difference(DateTime.now());
        Future<void>.delayed(delay, () async {
          await _sendCourseAnnouncementNow(
            text: scheduledText,
            selectedCourseIds: selectedIds,
            pinAnnouncements: shouldPin,
          );
        });

        courseMessageController.clear();
        scheduledCourseAnnouncementAt = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Announcement scheduled for ${TimeOfDay.fromDateTime(scheduledAt).format(context)}.',
              ),
            ),
          );
        }
        return;
      }

      await _sendCourseAnnouncementNow(
        text: text,
        selectedCourseIds: selectedCourseIds,
        pinAnnouncements: pinCourseAnnouncements,
      );

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

  Future<void> _sendCourseAnnouncementNow({
    required String text,
    required Set<String> selectedCourseIds,
    required bool pinAnnouncements,
  }) async {
    final selectedCourses = courses.where(
      (course) => selectedCourseIds.contains(course.id),
    );
    for (final course in selectedCourses) {
      final messageId = await FirestoreChatService.sendTextMessage(
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
        messageId: messageId,
        previewText: text,
        audience: 'course',
      );
      await FirestoreChatService.setAnnouncementPinned(
        courseId: course.id,
        pinned: pinAnnouncements,
      );
    }
  }

  Future<void> pickCourseAnnouncementSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: scheduledCourseAnnouncementAt ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(scheduledCourseAnnouncementAt ?? now),
    );
    if (time == null) return;

    setState(() {
      scheduledCourseAnnouncementAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
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
        final messageId = await FirestoreChatService.sendTextMessage(
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
          messageId: messageId,
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
              'Private message sent to $sentCount student${sentCount == 1 ? '' : 's'}.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Private message failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => sendingPrivateBroadcast = false);
    }
  }
}

class _CourseAnnouncementPanel extends StatelessWidget {
  static const templates = [
    'Reminder: please check your lesson schedule and be ready on time.',
    'Important update: today\'s session has a new note from EACC.',
    'Please review the attached materials before the next class.',
  ];

  final List<Course> courses;
  final TextEditingController controller;
  final TextEditingController filterController;
  final String filter;
  final Set<String> selectedCourseIds;
  final DateTime? scheduledAt;
  final bool pinAnnouncements;
  final bool isSending;
  final VoidCallback onChanged;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final VoidCallback onPickSchedule;
  final VoidCallback onClearSchedule;
  final ValueChanged<bool> onPinChanged;
  final ValueChanged<String> onUseTemplate;
  final VoidCallback onSend;

  const _CourseAnnouncementPanel({
    required this.courses,
    required this.controller,
    required this.filterController,
    required this.filter,
    required this.selectedCourseIds,
    required this.scheduledAt,
    required this.pinAnnouncements,
    required this.isSending,
    required this.onChanged,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.onPickSchedule,
    required this.onClearSchedule,
    required this.onPinChanged,
    required this.onUseTemplate,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final visibleCourses = courses.where((course) {
      if (filter.isEmpty) return true;
      final searchable = [
        course.id,
        course.displayName,
        course.category,
      ].join(' ').toLowerCase();
      return searchable.contains(filter);
    }).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.campaign_rounded,
              title: 'Course announcements',
              subtitle: 'Send one update to selected course announcement chats.',
            ),
            const SizedBox(height: 14),
            _FilterField(
              controller: filterController,
              query: filter,
              label: 'Find a course',
              hint: 'Search by course name, department, or ID',
              icon: Icons.menu_book_rounded,
              resultLabel:
                  '${visibleCourses.length} course${visibleCourses.length == 1 ? '' : 's'} shown',
              onChanged: onFilterChanged,
              onClear: onClearFilter,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: templates
                  .map(
                    (template) => ActionChip(
                      avatar: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: Text(
                        template.length > 34
                            ? '${template.substring(0, 34)}...'
                            : template,
                      ),
                      onPressed: () => onUseTemplate(template),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
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
            SwitchListTile(
              value: pinAnnouncements,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Keep announcement chat pinned',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Pinned announcements stay visible at the top of each course.',
              ),
              onChanged: onPinChanged,
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickSchedule,
                    icon: const Icon(Icons.event_rounded),
                    label: Text(
                      scheduledAt == null
                          ? 'Schedule'
                          : 'Scheduled ${TimeOfDay.fromDateTime(scheduledAt!).format(context)}',
                    ),
                  ),
                ),
                if (scheduledAt != null) ...[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onClearSchedule,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Clear schedule',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _SelectionToolbar(
              selected: selectedCourseIds.length,
              total: courses.length,
              visible: visibleCourses.length,
              onSelectAll: () {
                selectedCourseIds.addAll(
                  visibleCourses.map((course) => course.id),
                );
                onChanged();
              },
              onClear: () {
                selectedCourseIds.clear();
                onChanged();
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: visibleCourses.isEmpty
                  ? const _FilteredEmptyState(
                      icon: Icons.search_off_rounded,
                      message: 'No courses match this filter.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visibleCourses.length,
                      itemBuilder: (context, index) {
                        final course = visibleCourses[index];
                        return _CourseSelectionTile(
                          course: course,
                          selected: selectedCourseIds.contains(course.id),
                          onChanged: (value) {
                            if (value == true) {
                              selectedCourseIds.add(course.id);
                            } else {
                              selectedCourseIds.remove(course.id);
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
                label: const Text('Send announcement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseSelectionTile extends StatelessWidget {
  final Course course;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  const _CourseSelectionTile({
    required this.course,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreChatService.getAnnouncementThread(courseId: course.id),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final reads = data?['announcement_reads'];
        final readCount = FirestoreChatService.announcementStudentReadCount(
          reads,
        );
        final pinned = data?['pinned'] != false;

        return CheckboxListTile(
          value: selected,
          dense: true,
          title: Text(
            course.displayName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              Text('Course ${course.id}'),
              if (course.displayCategory != null)
                Text(course.displayCategory!),
              Text('$readCount read'),
              Text(pinned ? 'Pinned' : 'Unpinned'),
            ],
          ),
          secondary: Icon(
            pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            color: pinned ? AppColors.admin : AppColors.muted,
          ),
          onChanged: onChanged,
        );
      },
    );
  }
}

class _PrivateBroadcastPanel extends StatelessWidget {
  final List<_StudentTarget> targets;
  final TextEditingController controller;
  final TextEditingController filterController;
  final String filter;
  final Set<String> selectedStudentKeys;
  final bool isSending;
  final VoidCallback onChanged;
  final ValueChanged<String> onFilterChanged;
  final VoidCallback onClearFilter;
  final VoidCallback onSend;

  const _PrivateBroadcastPanel({
    required this.targets,
    required this.controller,
    required this.filterController,
    required this.filter,
    required this.selectedStudentKeys,
    required this.isSending,
    required this.onChanged,
    required this.onFilterChanged,
    required this.onClearFilter,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final visibleTargets = targets.where((target) {
      if (filter.isEmpty) return true;
      final searchable = [
        target.studentName,
        target.studentId,
        target.courseName,
        target.courseId,
      ].join(' ').toLowerCase();
      return searchable.contains(filter);
    }).toList(growable: false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.person_rounded,
              title: 'Private message to student',
              subtitle: 'Send a direct message to selected student chats.',
            ),
            const SizedBox(height: 14),
            _FilterField(
              controller: filterController,
              query: filter,
              label: 'Find a student',
              hint: 'Search by student name or ID',
              icon: Icons.person_search_rounded,
              resultLabel:
                  '${visibleTargets.length} student${visibleTargets.length == 1 ? '' : 's'} shown',
              onChanged: onFilterChanged,
              onClear: onClearFilter,
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
              visible: visibleTargets.length,
              onSelectAll: () {
                selectedStudentKeys.addAll(
                  visibleTargets.map((target) => target.key),
                );
                onChanged();
              },
              onClear: () {
                selectedStudentKeys.clear();
                onChanged();
              },
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: visibleTargets.isEmpty
                  ? const _FilteredEmptyState(
                      icon: Icons.person_off_outlined,
                      message: 'No students match this filter.',
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visibleTargets.length,
                      itemBuilder: (context, index) {
                        final target = visibleTargets[index];
                        final selected = selectedStudentKeys.contains(
                          target.key,
                        );
                        return _StudentTargetSelectionTile(
                          name: target.studentName,
                          studentId: target.studentId,
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
                label: const Text('Send private message'),
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

class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final String label;
  final String hint;
  final IconData icon;
  final String resultLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _FilterField({
    required this.controller,
    required this.query,
    required this.label,
    required this.hint,
    required this.icon,
    required this.resultLabel,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear filter',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: onChanged,
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              resultLabel,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  final int selected;
  final int total;
  final int visible;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  const _SelectionToolbar({
    required this.selected,
    required this.total,
    required this.visible,
    required this.onSelectAll,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TextButton(
          onPressed: visible == 0 ? null : onSelectAll,
          child: const Text('Select visible'),
        ),
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

class _FilteredEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _FilteredEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: AppColors.muted),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
  final String studentId;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StudentTargetSelectionTile({
    required this.name,
    required this.studentId,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              'ID $studentId',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
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
