import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../models/course.dart';
import '../services/auth_api.dart';
import '../services/firestore_chat_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/course_card.dart';
import '../widgets/polished_state_card.dart';
import '../widgets/screen_header.dart';
import 'admin_threads_screen.dart';

class AdminCoursesScreen extends StatefulWidget {
  final AuthSession session;

  const AdminCoursesScreen({super.key, required this.session});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
  final courseIdController = TextEditingController();
  Course? searchedCourse;
  bool isSearching = false;
  bool hasSearched = false;
  String searchQuery = '';
  String? searchError;
  String? searchNotice;
  int managerCourseTabIndex = 0;

  @override
  void dispose() {
    courseIdController.dispose();
    super.dispose();
  }

  Future<void> _searchCourse() async {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) return;

    setState(() {
      isSearching = true;
      hasSearched = true;
      searchError = null;
      searchNotice = null;
      searchedCourse = null;
      searchQuery = courseId;
    });

    final api = AuthApi();

    try {
      final sessionCourse = _findSessionCourse(courseId);
      final course = sessionCourse ?? await api.fetchCourse(courseId);
      if (mounted) {
        setState(() {
          searchedCourse = course;
          isSearching = false;
        });
      }
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      final canViewAllCourses = widget.session.appUser.canViewAllCourses;
      final canRefreshCourse =
          canViewAllCourses && !_isAuthErrorMessage(message);

      if (canRefreshCourse) {
        try {
          final refreshedCourse = await api.refreshCourse(courseId);
          if (mounted) {
            setState(() {
              searchedCourse = refreshedCourse;
              searchNotice =
                  'Course $courseId was refreshed from the LMS and saved to the app database.';
              isSearching = false;
            });
          }
          return;
        } catch (refreshError) {
          if (mounted) {
            setState(() {
              searchError = refreshError.toString().replaceFirst(
                'Exception: ',
                '',
              );
              isSearching = false;
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          searchError = message;
          isSearching = false;
        });
      }
    }
  }

  Course? _findSessionCourse(String courseId) {
    final normalized = courseId.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final course in widget.session.courses) {
      if (course.id.trim().toLowerCase() == normalized) {
        return course;
      }
    }

    return null;
  }

  void _onSearchQueryChanged(String value) {
    final normalized = value.trim().toLowerCase();

    setState(() {
      searchQuery = value;

      if (searchedCourse != null &&
          searchedCourse!.id.trim().toLowerCase() != normalized) {
        searchedCourse = null;
      }

      if (searchError != null || searchNotice != null) {
        searchError = null;
        searchNotice = null;
      }
    });
  }

  List<Course> _filterSessionCourses(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    return widget.session.courses
        .where((course) {
          return course.id.toLowerCase().contains(normalized) ||
              course.displayTitle.toLowerCase().contains(normalized) ||
              course.category.toLowerCase().contains(normalized) ||
              (course.teacherName?.toLowerCase().contains(normalized) ??
                  false) ||
              (course.keyPersonName?.toLowerCase().contains(normalized) ??
                  false);
        })
        .toList(growable: false);
  }

  List<Course> _linkedManagerCourses() {
    final adminId = widget.session.lmsUser.lmsUserId.trim().toLowerCase();
    final adminName = widget.session.appUser.name.trim().toLowerCase();

    return widget.session.courses
        .where((course) {
          final keyPersonId = course.keyPersonLmsUserId?.trim().toLowerCase();
          final keyPersonName = course.keyPersonName?.trim().toLowerCase();

          return (adminId.isNotEmpty && keyPersonId == adminId) ||
              (adminName.isNotEmpty && keyPersonName == adminName);
        })
        .toList(growable: false);
  }

  bool _isAuthErrorMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('secure session expired') ||
        normalized.contains('firebase bearer token') ||
        normalized.contains('unauthorized') ||
        normalized.contains('forbidden');
  }

  @override
  Widget build(BuildContext context) {
    final canViewAllCourses = widget.session.appUser.canViewAllCourses;
    final isSuperAdmin = widget.session.appUser.isSuperAdmin;
    final isManagerOperation = widget.session.appUser.isManagerOperation;
    final managerLinkedCourses = isManagerOperation
        ? _linkedManagerCourses()
        : const <Course>[];
    final showingManagerLinkedCourses =
        isManagerOperation && managerCourseTabIndex == 0;
    final hasSearchText = searchQuery.trim().isNotEmpty;
        final courses = showingManagerLinkedCourses
        ? managerLinkedCourses
        : isManagerOperation
        ? (searchedCourse != null ? [searchedCourse!] : const <Course>[])
        : canViewAllCourses
        ? (searchedCourse != null
              ? [searchedCourse!]
              : _filterSessionCourses(searchQuery))
        : widget.session.courses;

    return AppScaffold(
      title: canViewAllCourses ? 'Admin Courses' : 'Linked Courses',
      showLogout: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          ScreenHeader(
            title: 'Hello, ${widget.session.appUser.name}',
            subtitle: isSuperAdmin
                ? 'Full access is enabled. Search a course ID to view its chats.'
                : isManagerOperation
                ? 'Manager operation access is active. Search a course ID to view its chats.'
                : widget.session.courses.isEmpty
                ? 'No courses are linked to your contact-person account yet.'
                : 'Contact-person access is active. You can monitor only your linked courses.',
            icon: isSuperAdmin
                ? Icons.admin_panel_settings_rounded
                : isManagerOperation
                ? Icons.manage_accounts_rounded
                : Icons.verified_user_outlined,
          ),
          const SizedBox(height: 18),
          if (isManagerOperation) ...[
            _ManagerCourseScopeTabs(
              selectedIndex: managerCourseTabIndex,
              assignedCount: managerLinkedCourses.length,
              directoryCount: searchedCourse == null ? 0 : 1,
              onChanged: (index) {
                setState(() {
                  managerCourseTabIndex = index;
                });
              },
            ),
            const SizedBox(height: 18),
          ],
          if (canViewAllCourses && !showingManagerLinkedCourses) ...[
            _CourseLookupBar(
              controller: courseIdController,
              onSearch: _searchCourse,
              onChanged: _onSearchQueryChanged,
              isSearching: isSearching,
            ),
            const SizedBox(height: 18),
          ],
          if (!canViewAllCourses || courses.isNotEmpty) ...[
            _AccessSummary(
              session: widget.session,
              courses: courses,
              titleOverride: isManagerOperation
                  ? showingManagerLinkedCourses
                        ? 'Manager operation portfolio overview'
                        : 'Course directory overview'
                  : null,
            ),
            const SizedBox(height: 18),
          ],
          if (searchNotice != null) ...[
            _SearchNotice(message: searchNotice!),
            const SizedBox(height: 18),
          ],
          if (isSearching)
            const PolishedLoadingCard(
              title: 'Searching course',
              message: 'Checking your session and LMS course data.',
            )
          else if (canViewAllCourses &&
              !showingManagerLinkedCourses &&
              !hasSearched &&
              !hasSearchText)
            _EmptyState(
              icon: Icons.search_rounded,
              title: isManagerOperation
                  ? 'Find a course by ID'
                  : 'Search for a course',
              subtitle: isManagerOperation
                  ? 'Enter an LMS course ID to open that course from the directory.'
                  : 'Enter a course ID, name, teacher, or key person.',
            )
          else if (canViewAllCourses &&
              !showingManagerLinkedCourses &&
              searchedCourse == null &&
              courses.isEmpty)
            _EmptyState(
              icon: Icons.search_off_rounded,
              title: searchError == null
                  ? 'No matching course'
                  : 'Course not found',
              subtitle:
                  searchError ??
                  'No loaded course matches this search. Press Search to check the backend and refresh from the LMS.',
            )
          else if (courses.isEmpty)
            _EmptyState(
              icon: Icons.inventory_2_outlined,
              title: showingManagerLinkedCourses
                  ? 'No assigned courses'
                  : canViewAllCourses
                  ? 'No active courses'
                  : 'No linked courses',
              subtitle: showingManagerLinkedCourses
                  ? 'Courses assigned to your manager operation profile will appear here.'
                  : canViewAllCourses
                  ? 'Courses will appear here after they are synced.'
                  : 'Ask a full-access admin to assign you as contact person in the LMS, then log in again.',
            )
          else
            ...courses.map(
              (course) =>
                  _AdminCourseCard(course: course, session: widget.session),
            ),
        ],
      ),
    );
  }
}

class _SearchNotice extends StatelessWidget {
  final String message;

  const _SearchNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.warning.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.ink,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerCourseScopeTabs extends StatelessWidget {
  final int selectedIndex;
  final int assignedCount;
  final int directoryCount;
  final ValueChanged<int> onChanged;

  const _ManagerCourseScopeTabs({
    required this.selectedIndex,
    required this.assignedCount,
    required this.directoryCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final children = [
              _ManagerScopeButton(
                selected: selectedIndex == 0,
                icon: Icons.assignment_ind_rounded,
                title: 'Academic Portfolio',
                subtitle: '$assignedCount linked courses',
                onTap: () => onChanged(0),
              ),
              _ManagerScopeButton(
                selected: selectedIndex == 1,
                icon: Icons.travel_explore_rounded,
                title: 'Course Directory',
                subtitle: directoryCount == 0
                    ? 'Search by course ID'
                    : '$directoryCount course loaded',
                onTap: () => onChanged(1),
              ),
            ];

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [children[0], const SizedBox(height: 8), children[1]],
              );
            }

            return Row(
              children: [
                Expanded(child: children[0]),
                const SizedBox(width: 8),
                Expanded(child: children[1]),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ManagerScopeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ManagerScopeButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;

    return Material(
      color: selected
          ? AppColors.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.28)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: selected ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.ink : AppColors.muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? AppColors.primaryDark
                            : AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CourseLookupBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<String> onChanged;
  final bool isSearching;

  const _CourseLookupBar({
    required this.controller,
    required this.onSearch,
    required this.onChanged,
    required this.isSearching,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    final searchField = TextField(
      controller: controller,
      decoration: const InputDecoration(
        labelText: 'Course ID',
        hintText: 'Enter LMS Course ID, for example 2297',
        prefixIcon: Icon(Icons.search_rounded),
      ),
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: isSearching ? null : (_) => onSearch(),
    );

    final searchButton = SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: isSearching ? null : onSearch,
        icon: isSearching
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.search_rounded),
        label: Text(isSearching ? 'Searching' : 'Search'),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  searchField,
                  const SizedBox(height: 10),
                  searchButton,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 10),
                  searchButton,
                ],
              ),
      ),
    );
  }
}

class _AccessSummary extends StatelessWidget {
  final AuthSession session;
  final List<Course> courses;
  final String? titleOverride;

  const _AccessSummary({
    required this.session,
    required this.courses,
    this.titleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = session.appUser.isSuperAdmin;
    final isManagerOperation = session.appUser.isManagerOperation;
    final canViewAllCourses = session.appUser.canViewAllCourses;
    final studentCount = courses.fold<int>(
      0,
      (total, course) => total + course.students.length,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (isSuperAdmin ? AppColors.admin : AppColors.primary)
                        .withValues(alpha: 0.14),
                    (isSuperAdmin ? AppColors.admin : AppColors.primary)
                        .withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isSuperAdmin ? AppColors.admin : AppColors.primary)
                      .withValues(alpha: 0.15),
                ),
              ),
              child: Icon(
                isSuperAdmin
                    ? Icons.workspace_premium_outlined
                    : isManagerOperation
                    ? Icons.manage_accounts_rounded
                    : Icons.link_outlined,
                color: isSuperAdmin ? AppColors.admin : AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleOverride ??
                        (isSuperAdmin
                            ? 'Full access admin'
                            : canViewAllCourses
                            ? 'Manager operation courses and students'
                            : 'Contact manager courses and students'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${courses.length} ${courses.length == 1 ? 'course' : 'courses'}'
                    ' - $studentCount ${studentCount == 1 ? 'student' : 'students'}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      StreamBuilder<int>(
                        stream:
                            FirestoreChatService.getAdminUnreadTotalForCourses(
                              courses.map((course) => course.id),
                            ),
                        builder: (context, snapshot) {
                          final unread = snapshot.data ?? 0;
                          if (unread <= 0) return const SizedBox.shrink();

                          return _SummaryChip(
                            icon: Icons.mark_chat_unread_rounded,
                            label: unread == 1
                                ? '1 unread message'
                                : '$unread unread messages',
                            color: AppColors.danger,
                          );
                        },
                      ),
                      _SummaryChip(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'Chats',
                        color: AppColors.primary,
                      ),
                      _SummaryChip(
                        icon: Icons.campaign_rounded,
                        label: 'Announcements',
                        color: AppColors.admin,
                      ),
                      _SummaryChip(
                        icon: Icons.group_outlined,
                        label: 'Students',
                        color: AppColors.student,
                      ),
                      _SummaryChip(
                        icon: Icons.person_outline_rounded,
                        label: 'Teachers',
                        color: AppColors.teacher,
                      ),
                    ],
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

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCourseCard extends StatefulWidget {
  final Course course;
  final AuthSession session;

  const _AdminCourseCard({required this.course, required this.session});

  @override
  State<_AdminCourseCard> createState() => _AdminCourseCardState();
}

class _AdminCourseCardState extends State<_AdminCourseCard> {
  int? _lastUnreadCount;
  bool _isOpeningCourse = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AdminUnreadCounts>(
      stream: FirestoreChatService.getAdminUnreadCounts(
        courseId: widget.course.id,
      ),
      builder: (context, snapshot) {
        final counts = snapshot.data;
        final teacherUnread = counts?.teacherUnread ?? 0;
        final studentUnread = counts?.studentUnread ?? 0;

        final totalUnread = teacherUnread + studentUnread;
        _notifyIfIncreased(totalUnread);

        final List<Widget> customBadges = [];
        if (teacherUnread > 0) {
          customBadges.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.teacher.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.teacher.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                teacherUnread == 1
                    ? '1 teacher message'
                    : '$teacherUnread teacher messages',
                style: const TextStyle(
                  color: AppColors.teacher,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        if (studentUnread > 0) {
          customBadges.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                studentUnread == 1
                    ? '1 contact message'
                    : '$studentUnread contact messages',
                style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }

        return Stack(
          children: [
            CourseCard(
              course: widget.course,
              unreadCount: totalUnread,
              unreadLabel: totalUnread == 1
                  ? '1 unread total'
                  : '$totalUnread unread total',
              customBadges: customBadges.isNotEmpty ? customBadges : null,
              onTap: _openThreads,
            ),
            if (_isOpeningCourse)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Center(
                    child: _CourseOpeningPill(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _notifyIfIncreased(int totalUnread) {
    final previous = _lastUnreadCount;
    _lastUnreadCount = totalUnread;
    if (previous == null || totalUnread <= previous) return;
    if (!_canShowUnreadNotification()) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PushNotificationService.instance.showInAppNotification(
        title: widget.course.displayTitle,
        body: 'You have new unread messages in this course.',
        onOpen: _openThreads,
      );
    });
  }

  bool _canShowUnreadNotification() {
    final appUser = widget.session.appUser;
    if (!appUser.isManagerOperation) return true;

    final adminId = widget.session.lmsUser.lmsUserId.trim().toLowerCase();
    final adminName = appUser.name.trim().toLowerCase();
    final keyPersonId = widget.course.keyPersonLmsUserId?.trim().toLowerCase();
    final keyPersonName = widget.course.keyPersonName?.trim().toLowerCase();

    return (adminId.isNotEmpty && keyPersonId == adminId) ||
        (adminName.isNotEmpty && keyPersonName == adminName);
  }

  Future<void> _openThreads() async {
    if (_isOpeningCourse) return;

    setState(() => _isOpeningCourse = true);

    try {
      final course = await _loadCourseForOpen();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AdminThreadsScreen(
            courseId: course.id,
            courseName: course.displayTitle,
            teacherName: course.teacherName,
            keyPersonName: course.keyPersonName,
            students: course.students,
            session: widget.session,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load this course roster: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isOpeningCourse = false);
    }
  }

  Future<Course> _loadCourseForOpen() async {
    final appUser = widget.session.appUser;
    final shouldUseOnDemandDetail =
        appUser.canViewAllCourses || appUser.isManagerOperation;
    if (!shouldUseOnDemandDetail) return widget.course;

    final api = AuthApi();
    final cachedCourse = await api.fetchCourse(widget.course.id);
    if (cachedCourse.students.isNotEmpty) return cachedCourse;

    return api.refreshCourse(widget.course.id);
  }
}

class _CourseOpeningPill extends StatelessWidget {
  const _CourseOpeningPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Loading course roster...',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return PolishedStateCard(
      icon: icon,
      title: title,
      message: subtitle,
      color: icon == Icons.search_off_rounded
          ? AppColors.warning
          : AppColors.primary,
    );
  }
}




