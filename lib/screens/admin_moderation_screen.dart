import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';

class AdminModerationScreen extends StatefulWidget {
  final AuthSession session;

  const AdminModerationScreen({super.key, required this.session});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final searchController = TextEditingController();
  final selectedMessagePaths = <String>{};
  String query = '';
  bool isDeleting = false;

  bool get canBulkModerate => widget.session.appUser.isSuperAdmin;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Bulk Moderation',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreChatService.getRecentMessagesForModeration(limit: 160),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline_rounded,
              title: 'Could not load messages',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final visibleDocs = allDocs.where(_matchesSearch).toList();
          final selectedDocs = visibleDocs
              .where((doc) => selectedMessagePaths.contains(doc.reference.path))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Column(
                  children: [
                    if (!canBulkModerate) const _PermissionBanner(),
                    if (!canBulkModerate) const SizedBox(height: 10),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search messages, files, sender, course',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  searchController.clear();
                                  setState(() => query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: (value) {
                        setState(() => query = value.trim().toLowerCase());
                      },
                    ),
                    const SizedBox(height: 10),
                    _ModerationToolbar(
                      visibleCount: visibleDocs.length,
                      selectedCount: selectedDocs.length,
                      canBulkModerate: canBulkModerate,
                      isDeleting: isDeleting,
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
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visibleDocs.isEmpty
                    ? const _StateMessage(
                        icon: Icons.manage_search_rounded,
                        title: 'No matching messages',
                        message:
                            'Try another keyword or clear the search field.',
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
                                  selectedMessagePaths.remove(
                                    doc.reference.path,
                                  );
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
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
            'course_id': pathInfo.courseId,
            'thread_id': pathInfo.threadId,
            'message_id': doc.id,
          },
        );
      }

      if (!mounted) return;
      setState(selectedMessagePaths.clear);
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

class _ModerationToolbar extends StatelessWidget {
  final int visibleCount;
  final int selectedCount;
  final bool canBulkModerate;
  final bool isDeleting;
  final VoidCallback onSelectVisible;
  final VoidCallback onClear;
  final VoidCallback? onDelete;

  const _ModerationToolbar({
    required this.visibleCount,
    required this.selectedCount,
    required this.canBulkModerate,
    required this.isDeleting,
    required this.onSelectVisible,
    required this.onClear,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            '$visibleCount messages shown',
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
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
          const SizedBox(width: 6),
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
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: canSelect ? onChanged : null),
            const SizedBox(width: 8),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.admin.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.primary),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
