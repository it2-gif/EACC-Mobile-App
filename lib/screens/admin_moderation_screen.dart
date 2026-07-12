import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/polished_state_card.dart';

class AdminModerationScreen extends StatefulWidget {
  final AuthSession session;

  const AdminModerationScreen({super.key, required this.session});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final courseIdController = TextEditingController();
  final searchController = TextEditingController();
  final selectedMessagePaths = <String>{};
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? messagesFuture;
  String loadedCourseId = '';
  String query = '';
  bool isDeleting = false;

  bool get canBulkModerate => widget.session.appUser.isSuperAdmin;

  @override
  void dispose() {
    courseIdController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Moderations',
      body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
        future: messagesFuture,
        builder: (context, snapshot) {
          if (messagesFuture == null) {
            return _ModerationShell(
              canBulkModerate: canBulkModerate,
              courseIdController: courseIdController,
              searchController: searchController,
              query: query,
              enabledSearch: false,
              onLoad: _loadCourseMessages,
              onClearSearch: _clearSearch,
              onSearchChanged: (value) {
                setState(() => query = value.trim().toLowerCase());
              },
              child: const _StateMessage(
                icon: Icons.filter_alt_rounded,
                title: 'Choose a course first',
                message:
                    'Enter a course ID to load its 100 most recent messages only.',
              ),
            );
          }

          if (snapshot.hasError) {
            return _ModerationShell(
              canBulkModerate: canBulkModerate,
              courseIdController: courseIdController,
              searchController: searchController,
              query: query,
              enabledSearch: false,
              onLoad: _loadCourseMessages,
              onClearSearch: _clearSearch,
              onSearchChanged: (value) {
                setState(() => query = value.trim().toLowerCase());
              },
              child: _StateMessage(
                icon: Icons.error_outline_rounded,
                title: 'Could not load messages',
                message: '${snapshot.error}',
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return _ModerationShell(
              canBulkModerate: canBulkModerate,
              courseIdController: courseIdController,
              searchController: searchController,
              query: query,
              enabledSearch: false,
              onLoad: _loadCourseMessages,
              onClearSearch: _clearSearch,
              onSearchChanged: (value) {
                setState(() => query = value.trim().toLowerCase());
              },
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: PolishedLoadingCard(
                  title: 'Loading messages',
                  message: 'Fetching the latest course messages for review.',
                ),
              ),
            );
          }

          final allDocs = snapshot.data ?? [];
          final visibleDocs = allDocs.where(_matchesSearch).toList();
          final selectedDocs = visibleDocs
              .where((doc) => selectedMessagePaths.contains(doc.reference.path))
              .toList();

          return _ModerationShell(
            canBulkModerate: canBulkModerate,
            courseIdController: courseIdController,
            searchController: searchController,
            query: query,
            enabledSearch: true,
            onLoad: _loadCourseMessages,
            onClearSearch: _clearSearch,
            onSearchChanged: (value) {
              setState(() => query = value.trim().toLowerCase());
            },
            toolbar: _ModerationToolbar(
              visibleCount: visibleDocs.length,
              selectedCount: selectedDocs.length,
              canBulkModerate: canBulkModerate,
              isDeleting: isDeleting,
              loadedCourseId: loadedCourseId,
              onSelectVisible: () {
                setState(() {
                  for (final doc in visibleDocs) {
                    if (doc.data()['deleted_at'] == null) {
                      selectedMessagePaths.add(doc.reference.path);
                    }
                  }
                });
              },
              onClear: () => setState(selectedMessagePaths.clear),
              onDelete: selectedDocs.isEmpty
                  ? null
                  : () => _deleteSelected(selectedDocs),
              onRefresh: _refreshLoadedCourse,
            ),
            child: visibleDocs.isEmpty
                ? _StateMessage(
                    icon: Icons.manage_search_rounded,
                    title: allDocs.isEmpty
                        ? 'No messages in this course'
                        : 'No matching messages',
                    message: allDocs.isEmpty
                        ? 'Course $loadedCourseId has no loaded messages yet.'
                        : 'Try another keyword or clear the search field.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    itemCount: visibleDocs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = visibleDocs[index];
                      final data = doc.data();
                      final deleted = data['deleted_at'] != null;
                      final selected = selectedMessagePaths.contains(
                        doc.reference.path,
                      );

                      return _ModerationMessageTile(
                        data: data,
                        reference: doc.reference,
                        selected: selected,
                        canSelect: canBulkModerate && !deleted,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              selectedMessagePaths.add(doc.reference.path);
                            } else {
                              selectedMessagePaths.remove(doc.reference.path);
                            }
                          });
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  void _loadCourseMessages() {
    final courseId = courseIdController.text.trim();
    if (courseId.isEmpty) return;

    setState(() {
      loadedCourseId = courseId;
      selectedMessagePaths.clear();
      messagesFuture =
          FirestoreChatService.getRecentCourseMessagesForModeration(
            courseId: courseId,
          );
    });
  }

  void _refreshLoadedCourse() {
    if (loadedCourseId.isEmpty) return;
    setState(() {
      selectedMessagePaths.clear();
      messagesFuture =
          FirestoreChatService.getRecentCourseMessagesForModeration(
            courseId: loadedCourseId,
          );
    });
  }

  void _clearSearch() {
    searchController.clear();
    setState(() => query = '');
  }

  bool _matchesSearch(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    if (query.isEmpty) return true;
    final data = doc.data();
    final pathInfo = _MessagePathInfo.fromReference(doc.reference);
    final haystack = [
      data['sender_name'],
      data['sender_role'],
      data['type'],
      data['file_name'],
      _messagePreview(data),
      pathInfo.courseId,
      pathInfo.threadId,
      doc.id,
    ].whereType<Object>().join(' ').toLowerCase();

    return haystack.contains(query);
  }

  Future<void> _deleteSelected(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> selectedDocs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete selected messages?'),
        content: Text(
          'This will soft-delete ${selectedDocs.length} message${selectedDocs.length == 1 ? '' : 's'} and write an audit log.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isDeleting = true);
    var deletedCount = 0;

    try {
      for (final doc in selectedDocs) {
        final pathInfo = _MessagePathInfo.fromReference(doc.reference);
        await FirestoreChatService.deleteMessageByReference(
          messageRef: doc.reference,
          deletedByRole: widget.session.appUser.role,
          deletedByName: widget.session.appUser.name,
        );
        deletedCount++;
        await FirestoreChatService.logAuditEvent(
          actorRole: widget.session.appUser.role,
          actorName: widget.session.appUser.name,
          action: 'bulk_message_deleted',
          resourceType: 'message',
          resourceId: doc.id,
          metadata: {
            'preview': _messagePreview(doc.data()),
            'sender_name': doc.data()['sender_name']?.toString() ?? '',
            'sender_role': doc.data()['sender_role']?.toString() ?? '',
            'course_id': pathInfo.courseId,
            'thread_id': pathInfo.threadId,
            'message_id': doc.id,
          },
        );
      }

      if (!mounted) return;
      setState(selectedMessagePaths.clear);
      _refreshLoadedCourse();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deletedCount selected message(s).')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Bulk moderation failed: $error')));
    } finally {
      if (mounted) setState(() => isDeleting = false);
    }
  }

  String _messagePreview(Map<String, dynamic> data) {
    if (data['deleted_at'] != null) return 'Deleted message';
    final text = data['text']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;

    final type = data['type']?.toString() ?? 'message';
    final fileName = data['file_name']?.toString().trim() ?? '';
    if (fileName.isNotEmpty) return fileName;

    return switch (type) {
      'image' => 'Photo',
      'video' => 'Video',
      'voice' => 'Voice message',
      'document' => 'Document',
      _ => 'Message',
    };
  }
}

class _ModerationShell extends StatelessWidget {
  final bool canBulkModerate;
  final TextEditingController courseIdController;
  final TextEditingController searchController;
  final String query;
  final bool enabledSearch;
  final VoidCallback onLoad;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onSearchChanged;
  final Widget? toolbar;
  final Widget child;

  const _ModerationShell({
    required this.canBulkModerate,
    required this.courseIdController,
    required this.searchController,
    required this.query,
    required this.enabledSearch,
    required this.onLoad,
    required this.onClearSearch,
    required this.onSearchChanged,
    required this.child,
    this.toolbar,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 620;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            children: [
              if (!canBulkModerate) const _PermissionBanner(),
              if (!canBulkModerate) const SizedBox(height: 10),
              Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (compact)
                    TextField(
                      controller: courseIdController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        hintText: 'Course ID, for example 2203',
                        labelText: 'Course ID',
                        prefixIcon: Icon(Icons.filter_alt_rounded),
                      ),
                      onSubmitted: (_) => onLoad(),
                    )
                  else
                    Expanded(
                      child: TextField(
                        controller: courseIdController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          hintText: 'Course ID, for example 2203',
                          labelText: 'Course ID',
                          prefixIcon: Icon(Icons.filter_alt_rounded),
                        ),
                        onSubmitted: (_) => onLoad(),
                      ),
                    ),
                  SizedBox(width: compact ? 0 : 10, height: compact ? 10 : 0),
                  FilledButton.icon(
                    onPressed: onLoad,
                    icon: const Icon(Icons.manage_search_rounded),
                    label: const Text('Load'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: searchController,
                enabled: enabledSearch,
                decoration: InputDecoration(
                  hintText: enabledSearch
                      ? 'Search loaded messages, files, sender'
                      : 'Load a course before searching',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: onClearSearch,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                onChanged: onSearchChanged,
              ),
              if (toolbar != null) ...[const SizedBox(height: 10), toolbar!],
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ModerationToolbar extends StatelessWidget {
  final int visibleCount;
  final int selectedCount;
  final bool canBulkModerate;
  final bool isDeleting;
  final String loadedCourseId;
  final VoidCallback onSelectVisible;
  final VoidCallback onClear;
  final VoidCallback onRefresh;
  final VoidCallback? onDelete;

  const _ModerationToolbar({
    required this.visibleCount,
    required this.selectedCount,
    required this.canBulkModerate,
    required this.isDeleting,
    required this.loadedCourseId,
    required this.onSelectVisible,
    required this.onClear,
    required this.onRefresh,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Pill(label: '$visibleCount messages', color: AppColors.primary),
            _Pill(label: 'Course $loadedCourseId', color: AppColors.admin),
            IconButton.filledTonal(
              tooltip: 'Refresh course messages',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (canBulkModerate) ...[
              TextButton(
                onPressed: onSelectVisible,
                child: const Text('Select visible'),
              ),
              TextButton(
                onPressed: selectedCount == 0 ? null : onClear,
                child: const Text('Clear'),
              ),
              FilledButton.icon(
                onPressed: isDeleting ? null : onDelete,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: Text(
                  selectedCount == 0 ? 'Delete' : 'Delete $selectedCount',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModerationMessageTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> reference;
  final bool selected;
  final bool canSelect;
  final ValueChanged<bool?> onChanged;

  const _ModerationMessageTile({
    required this.data,
    required this.reference,
    required this.selected,
    required this.canSelect,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pathInfo = _MessagePathInfo.fromReference(reference);
    final deleted = data['deleted_at'] != null;
    final senderName = data['sender_name']?.toString() ?? 'Unknown sender';
    final senderRole = data['sender_role']?.toString() ?? 'role';
    final preview = _messagePreview(data);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: canSelect ? onChanged : null),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text(
                        formatThreadTime(data['created_at']),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: deleted ? AppColors.muted : AppColors.ink,
                      fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(label: senderRole),
                      _Pill(label: 'Course ${pathInfo.courseId}'),
                      _Pill(label: 'Thread ${pathInfo.threadId}'),
                      if (deleted)
                        const _Pill(label: 'Deleted', color: AppColors.danger),
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

  String _messagePreview(Map<String, dynamic> data) {
    if (data['deleted_at'] != null) return 'Deleted message';
    final text = data['text']?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;

    final type = data['type']?.toString() ?? 'message';
    final fileName = data['file_name']?.toString().trim() ?? '';
    if (fileName.isNotEmpty) return fileName;

    return switch (type) {
      'image' => 'Photo',
      'video' => 'Video',
      'voice' => 'Voice message',
      'document' => 'Document',
      _ => 'Message',
    };
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.admin.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.admin.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: AppColors.admin),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bulk delete is limited to super admin accounts. Standard admins can review activity only.',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MessagePathInfo {
  final String courseId;
  final String threadId;

  const _MessagePathInfo({required this.courseId, required this.threadId});

  factory _MessagePathInfo.fromReference(DocumentReference reference) {
    final segments = reference.path.split('/');
    return _MessagePathInfo(
      courseId: segments.length > 1 ? segments[1] : 'unknown',
      threadId: segments.length > 3 ? segments[3] : 'unknown',
    );
  }
}

class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _StateMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: PolishedStateCard(
        icon: icon,
        title: title,
        message: message,
        color: icon == Icons.error_outline_rounded
            ? AppColors.danger
            : AppColors.primary,
      ),
    );
  }
}
