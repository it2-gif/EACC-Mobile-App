import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/auth_session.dart';
import '../services/firestore_chat_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/app_scaffold.dart';

class AdminAuditScreen extends StatelessWidget {
  final AuthSession session;

  const AdminAuditScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Audit Trail',
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreChatService.getAuditLogs(limit: 120),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.error_outline_rounded,
              title: 'Could not load audit logs',
              message: '${snapshot.error}',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _StateMessage(
              icon: Icons.manage_search_rounded,
              title: 'No audit activity yet',
              message:
                  'Message edits, deletes, pins, and bulk moderation will appear here.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              return _AuditLogTile(data: data);
            },
          );
        },
      ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  final Map<String, dynamic> data;

  const _AuditLogTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final action = _titleCase(data['action']?.toString() ?? 'activity');
    final actorName = data['actor_name']?.toString() ?? 'Unknown user';
    final actorRole = data['actor_role']?.toString() ?? 'role';
    final resourceType = data['resource_type']?.toString() ?? 'resource';
    final resourceId = data['resource_id']?.toString() ?? '';
    final metadata = data['metadata'];
    final messagePreview = _messagePreview(metadata);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _actionColor(action).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_actionIcon(action), color: _actionColor(action)),
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
                          action,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
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
                    '$actorName ($actorRole) changed $resourceType',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (messagePreview.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        messagePreview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  if (resourceId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _MetaPill(label: 'Message ID $resourceId'),
                  ],
                  if (metadata is Map && metadata.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: metadata.entries
                          .where(
                            (entry) =>
                                entry.value != null &&
                                !{
                                  'preview',
                                  'previous_text',
                                  'text',
                                  'file_name',
                                }.contains(entry.key.toString()),
                          )
                          .map(
                            (entry) => _MetaPill(
                              label: '${entry.key}: ${entry.value}',
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleCase(String value) {
    return value
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  IconData _actionIcon(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('delete')) return Icons.delete_outline_rounded;
    if (lower.contains('pin')) return Icons.push_pin_rounded;
    if (lower.contains('bulk')) return Icons.library_add_check_rounded;
    return Icons.edit_note_rounded;
  }

  Color _actionColor(String action) {
    final lower = action.toLowerCase();
    if (lower.contains('delete')) return AppColors.danger;
    if (lower.contains('pin')) return AppColors.admin;
    return AppColors.primary;
  }

  String _messagePreview(Object? metadata) {
    if (metadata is! Map) return '';

    for (final key in ['preview', 'text', 'file_name']) {
      final value = metadata[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    return '';
  }
}

class _MetaPill extends StatelessWidget {
  final String label;

  const _MetaPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
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
