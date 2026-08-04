import 'package:flutter/material.dart';

import '../models/course.dart';
import '../theme/app_theme.dart';
import 'unread_badge.dart';

class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;
  final int unreadCount;
  final String? unreadLabel;
  final List<Widget>? customBadges;

  const CourseCard({
    super.key,
    required this.course,
    required this.onTap,
    this.unreadCount = 0,
    this.unreadLabel,
    this.customBadges,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 420;
    final hasTeacher =
        course.teacherName != null && course.teacherName!.trim().isNotEmpty;
    final hasKeyPerson =
        course.keyPersonName != null && course.keyPersonName!.trim().isNotEmpty;
    final unread = unreadCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        shadowColor: AppColors.primaryDark.withValues(alpha: 0.08),
        elevation: unread ? 1.2 : 0.4,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: unread
                    ? AppColors.primary.withValues(alpha: 0.25)
                    : AppColors.border,
              ),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 4,
                    decoration: BoxDecoration(
                      color: unread ? AppColors.primary : Colors.transparent,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(22),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 14,
                        compact ? 12 : 14,
                        compact ? 12 : 14,
                        compact ? 12 : 14,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _CourseAvatar(
                            label: course.displayTitle,
                            unread: unread,
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        course.displayTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppColors.ink,
                                          fontWeight: unread
                                              ? FontWeight.w900
                                              : FontWeight.w800,
                                          fontSize: compact ? 15 : 16,
                                          height: 1.15,
                                        ),
                                      ),
                                    ),
                                    if (unread) ...[
                                      const SizedBox(width: 8),
                                      UnreadBadge(
                                        count: unreadCount,
                                        compact: true,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  _subtitle(hasTeacher),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12.5,
                                    height: 1.25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    _CourseChip(
                                      icon: Icons.tag_rounded,
                                      label: 'Course ${course.id}',
                                    ),
                                    ...?customBadges,
                                    if (hasTeacher)
                                      _CourseChip(
                                        icon: Icons.person_outline_rounded,
                                        label: course.teacherName!.trim(),
                                      ),
                                    if (hasKeyPerson)
                                      _CourseChip(
                                        icon: Icons.verified_user_outlined,
                                        label: course.keyPersonName!.trim(),
                                        color: AppColors.primary,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: unread
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: unread
                                  ? AppColors.primary
                                  : AppColors.primaryDark,
                              size: 21,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(bool hasTeacher) {
    final category = course.displayCategory?.trim();
    if (category != null && category.isNotEmpty) return category;
    if (hasTeacher) return 'Open student conversations';
    return 'Open course chat';
  }
}

class _CourseAvatar extends StatelessWidget {
  final String label;
  final bool unread;

  const _CourseAvatar({required this.label, required this.unread});

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? 'C' : label.trim()[0].toUpperCase();

    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: unread
              ? [AppColors.primary, AppColors.primaryDark]
              : [
                  AppColors.primary.withValues(alpha: 0.13),
                  AppColors.sky.withValues(alpha: 0.72),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unread
              ? Colors.white.withValues(alpha: 0.3)
              : AppColors.primary.withValues(alpha: 0.13),
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: unread ? Colors.white : AppColors.primary,
          fontSize: 19,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CourseChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CourseChip({
    required this.icon,
    required this.label,
    this.color = AppColors.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color == AppColors.muted ? AppColors.muted : color,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
