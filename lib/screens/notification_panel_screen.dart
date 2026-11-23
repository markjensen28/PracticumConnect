import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../services/practicum_repository.dart';
import 'document_workflow_screens.dart';
import 'student_profile_screen.dart';
import 'workflow_shared.dart';
import 'workspace_select_field.dart';

class StudentNotificationPanelScreen extends StatefulWidget {
  const StudentNotificationPanelScreen({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final PracticumRepository repository;

  @override
  State<StudentNotificationPanelScreen> createState() =>
      _StudentNotificationPanelScreenState();
}

class _StudentNotificationPanelScreenState
    extends State<StudentNotificationPanelScreen> {
  static const _typeLabels = {
    'all': 'All Types',
    'general': 'General',
    'document_feedback': 'Document Feedback',
    'deadline': 'Deadline',
    'verification_reminder': 'Verification reminder',
    'status_update': 'Status Update',
    'document_submission': 'Document Submission',
    'dtr_submission': 'DTR Submission',
    'dtr_update': 'DTR Update',
    'assignment': 'Assignment',
    'evaluation': 'Evaluation',
  };

  String _query = '';
  String _type = 'all';
  String _dateFilter = 'All Dates';
  int _tab = 0;
  NotificationRecord? _selected;

  Future<void> _selectNotification(NotificationRecord notice) async {
    setState(() => _selected = notice);
    if (!notice.isReadBy(widget.user.uid)) {
      await widget.repository.markNotificationRead(
        user: widget.user,
        notification: notice,
      );
    }
  }

  Future<void> _openNotification(NotificationRecord notice) async {
    setState(() => _selected = notice);

    if (!notice.isReadBy(widget.user.uid)) {
      await widget.repository.markNotificationRead(
        user: widget.user,
        notification: notice,
      );
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _NotificationDetailPage(
          user: widget.user,
          notice: notice,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _deleteNotificationForMe(NotificationRecord notice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notification?'),
        content: Text(
          'Remove "${notice.title}" from your notifications? '
          'This only removes it from your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.repository.dismissNotificationForUser(
        user: widget.user,
        notification: notice,
      );

      if (!mounted) return;

      if (_selected?.id == notice.id) {
        setState(() => _selected = null);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification removed from your account.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete notification: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NotificationRecord>>(
    stream: widget.repository.watchNotifications(widget.user),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Text('Unable to load notifications: ${snapshot.error}'),
        );
      }

      final all = snapshot.data ?? const <NotificationRecord>[];
      final unread = all
          .where((notice) => !notice.isReadBy(widget.user.uid))
          .toList();
      final counts = [
        all.length,
        unread.length,
        all.where((notice) => notice.type == 'deadline').length,
        all.where((notice) => notice.type == 'status_update').length,
        all.where((notice) => notice.type == 'document_feedback').length,
      ];
      final records = all.where((notice) {
        final tabMatches = switch (_tab) {
          1 => !notice.isReadBy(widget.user.uid),
          2 => notice.type == 'deadline',
          3 => notice.type == 'status_update',
          4 => notice.type == 'document_feedback',
          _ => true,
        };
        final queryMatches =
            _query.isEmpty ||
            '${notice.title} ${notice.message}'.toLowerCase().contains(_query);
        final typeMatches = _type == 'all' || notice.type == _type;
        final now = DateTime.now();
        final created = notice.deliveryTime;
        final dateMatches = switch (_dateFilter) {
          'Today' =>
            created.year == now.year &&
                created.month == now.month &&
                created.day == now.day,
          'Last 7 Days' => created.isAfter(
            now.subtract(const Duration(days: 7)),
          ),
          'Last 30 Days' => created.isAfter(
            now.subtract(const Duration(days: 30)),
          ),
          _ => true,
        };
        return tabMatches && queryMatches && typeMatches && dateMatches;
      }).toList();
      final selected =
          _selected != null &&
              records.any((notice) => notice.id == _selected!.id)
          ? records.firstWhere((notice) => notice.id == _selected!.id)
          : records.firstOrNull;

      return WorkflowPage(
        title: 'Notifications',
        subtitle: widget.user.role == UserRole.student
            ? 'View internship updates, reminders, document feedback, and deadlines.'
            : 'View assigned-intern submissions, status changes, DTR updates, and evaluation notices.',
        eyebrow: 'Home  ›  Notifications',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: WorkspaceTabs(
                    labels: const [
                      'All',
                      'Unread',
                      'Deadlines',
                      'Status Updates',
                      'Document Feedback',
                    ],
                    counts: counts,
                    selectedIndex: _tab,
                    onSelected: (value) => setState(() => _tab = value),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: unread.isEmpty
                      ? null
                      : () async {
                          for (final notice in unread) {
                            await widget.repository.markNotificationRead(
                              user: widget.user,
                              notification: notice,
                            );
                          }
                        },
                  icon: const Icon(Icons.mark_email_read_outlined, size: 15),
                  label: const Text('Mark all as read'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 10.0;
                  final wide = constraints.maxWidth >= 660;
                  final filterWidth = constraints.maxWidth - spacing;
                  final typeWidth = wide ? 210.0 : filterWidth * .55;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: wide ? 270 : constraints.maxWidth,
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 18),
                            hintText: 'Search notifications…',
                          ),
                          onChanged: (value) =>
                              setState(() => _query = value.toLowerCase()),
                        ),
                      ),
                      SizedBox(
                        width: typeWidth,
                        child: WorkspaceSelectField(
                          label: 'Type',
                          initialValue: _type,
                          options: _typeLabels.keys.toList(),
                          optionLabel: (type) => _typeLabels[type]!,
                          onChanged: (value) => setState(() => _type = value),
                        ),
                      ),
                      SizedBox(
                        width: wide ? 160 : filterWidth - typeWidth,
                        child: WorkspaceSelectField(
                          label: 'Date',
                          initialValue: _dateFilter,
                          options: const [
                            'All Dates',
                            'Today',
                            'Last 7 Days',
                            'Last 30 Days',
                          ],
                          onChanged: (value) =>
                              setState(() => _dateFilter = value),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final list = _NotificationList(
                    records: records,
                    user: widget.user,
                    selected: selected,
                    onSelect: constraints.maxWidth < 960
                        ? _openNotification
                        : _selectNotification,
                    onView: _openNotification,
                    onDelete: _deleteNotificationForMe,
                  );
                  final details = selected == null
                      ? const EmptyWorkflowState(
                          icon: Icons.mark_email_unread_outlined,
                          title: 'Select a notification',
                          message:
                              'Notification details and actions appear here.',
                        )
                      : _NotificationDetails(
                          user: widget.user,
                          notice: selected,
                          repository: widget.repository,
                        );
                  if (constraints.maxWidth < 960) return list;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: list),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 4,
                        child: SingleChildScrollView(child: details),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.records,
    required this.user,
    required this.selected,
    required this.onSelect,
    required this.onView,
    required this.onDelete,
  });

  final List<NotificationRecord> records;
  final AppUser user;
  final NotificationRecord? selected;
  final ValueChanged<NotificationRecord> onSelect;
  final ValueChanged<NotificationRecord> onView;
  final ValueChanged<NotificationRecord> onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: records.isEmpty
        ? const EmptyWorkflowState(
            icon: Icons.notifications_none_outlined,
            title: 'No notifications',
            message: 'New internship updates will appear here.',
          )
        : ListView.separated(
            itemCount: records.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notice = records[index];
              final unread = !notice.isReadBy(user.uid);
              final active = selected?.id == notice.id;
              return InkWell(
                onTap: () => onSelect(notice),
                child: Container(
                  color: active
                      ? AppTheme.surfaceBlue
                      : unread
                      ? AppTheme.surface
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: unread ? AppTheme.blue : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        _noticeIcon(notice.type),
                        size: 21,
                        color: unread ? AppTheme.blue : AppTheme.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notice.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              notice.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: AppTheme.fontSmall,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateFormat.MMMd().add_jm().format(
                                notice.deliveryTime,
                              ),
                              style: const TextStyle(
                                color: AppTheme.muted,
                                fontSize: AppTheme.fontCaption,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      MenuAnchor(
                        style: workspaceMenuStyle(
                          width: 152,
                          alignment: AlignmentDirectional.bottomEnd,
                        ),
                        alignmentOffset: const Offset(0, 6),
                        menuChildren: [
                          MenuItemButton(
                            style: workspaceMenuItemStyle(),
                            leadingIcon: const Icon(
                              Icons.visibility_outlined,
                              size: 18,
                            ),
                            onPressed: () => onView(notice),
                            child: const Text('View'),
                          ),
                          MenuItemButton(
                            style: workspaceMenuItemStyle(),
                            leadingIcon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: AppTheme.danger,
                            ),
                            onPressed: () => onDelete(notice),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ),
                        ],
                        builder: (context, menu, child) => Semantics(
                          expanded: menu.isOpen,
                          child: IconButton(
                            tooltip: 'Notification actions',
                            onPressed: () =>
                                menu.isOpen ? menu.close() : menu.open(),
                            icon: const Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
  );
}

class _NotificationDetailPage extends StatelessWidget {
  const _NotificationDetailPage({
    required this.user,
    required this.notice,
    required this.repository,
  });

  final AppUser user;
  final NotificationRecord notice;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(title: const Text('Notification')),
    body: SafeArea(
      child: StreamBuilder<List<NotificationRecord>>(
        stream: repository.watchNotifications(user),
        builder: (context, snapshot) {
          final records = snapshot.data ?? const <NotificationRecord>[];

          final current = records
              .where((item) => item.id == notice.id)
              .firstOrNull;

          final shownNotice = current ?? notice;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: _NotificationDetails(
                  user: user,
                  notice: shownNotice,
                  repository: repository,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _NotificationDetails extends StatelessWidget {
  const _NotificationDetails({
    required this.user,
    required this.notice,
    required this.repository,
  });

  final AppUser user;
  final NotificationRecord notice;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: notice.title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          DateFormat.yMMMd().add_jm().format(notice.deliveryTime),
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: AppTheme.fontCaption,
          ),
        ),
        const Divider(height: 20),
        InfoRow('From', 'PracticumConnect System', labelWidth: 88),
        InfoRow('Category', _typeLabel(notice.type), labelWidth: 88),
        if (notice.relatedId != null)
          InfoRow('Related', _relatedLabel(), labelWidth: 88),
        const Divider(height: 20),
        const Text(
          'Message',
          style: TextStyle(
            fontSize: AppTheme.fontCaption,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          notice.message,
          style: const TextStyle(
            color: AppTheme.muted,
            fontSize: AppTheme.fontBody,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        if (user.role == UserRole.coordinator &&
            notice.type == 'assignment' &&
            notice.relatedId?.isNotEmpty == true) ...[
          FilledButton.icon(
            onPressed: () async {
              try {
                final student = await repository.getStudentById(
                  notice.relatedId!,
                );
                if (!context.mounted) return;
                if (student == null ||
                    student.coordinatorId != user.uid ||
                    !user.canCoordinate(student)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Student profile unavailable. Ask the SIP Admin to verify the assignment.',
                      ),
                    ),
                  );
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      backgroundColor: AppTheme.background,
                      appBar: AppBar(title: const Text('Student Profile')),
                      body: Padding(
                        padding: const EdgeInsets.all(18),
                        child: StudentInternshipProfileScreen(
                          actor: user,
                          student: student,
                          repository: repository,
                        ),
                      ),
                    ),
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Student profile unavailable. Ask the SIP Admin to verify the assignment.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.person_search_outlined, size: 16),
            label: const Text('Open Student Profile'),
          ),
          const SizedBox(height: 7),
        ],
        if (user.role == UserRole.student &&
            notice.relatedId != null &&
            (notice.type == 'document_feedback' ||
                notice.type == 'document_submission')) ...[
          FilledButton.icon(
            onPressed: () async {
              final record = await repository.getRequirement(notice.relatedId!);
              if (!context.mounted) return;
              if (record == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('The related requirement is not available.'),
                  ),
                );
                return;
              }
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: AppTheme.background,
                    appBar: AppBar(title: const Text('Document Submission')),
                    body: Padding(
                      padding: const EdgeInsets.all(18),
                      child: DocumentSubmissionBinScreen(
                        user: user,
                        repository: repository,
                        initialDefinitionId: record.definitionId,
                      ),
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.description_outlined, size: 15),
            label: const Text('View Requirement'),
          ),
          const SizedBox(height: 7),
        ],
        if (user.role == UserRole.coordinator &&
            (notice.type == 'verification_reminder' ||
                notice.type == 'document_submission' ||
                notice.type == 'document_feedback')) ...[
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Document Review')),
                  body: Padding(
                    padding: const EdgeInsets.all(18),
                    child: DocumentReviewScreen(
                      user: user,
                      repository: repository,
                    ),
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.rate_review_outlined, size: 15),
            label: const Text('Open Document Review'),
          ),
          const SizedBox(height: 7),
        ],
        if (user.role == UserRole.student) ...[
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Status Tracker')),
                  body: Padding(
                    padding: const EdgeInsets.all(18),
                    child: StudentStatusTrackerScreen(
                      user: user,
                      repository: repository,
                    ),
                  ),
                ),
              ),
            ),
            icon: const Icon(Icons.track_changes_outlined, size: 15),
            label: const Text('Open Status Tracker'),
          ),
          const SizedBox(height: 7),
        ],
        if (!notice.isReadBy(user.uid))
          OutlinedButton.icon(
            onPressed: () => repository.markNotificationRead(
              user: user,
              notification: notice,
            ),
            icon: const Icon(Icons.mark_email_read_outlined, size: 15),
            label: const Text('Mark as Read'),
          ),
      ],
    ),
  );

  String _relatedLabel() {
    if (notice.type != 'assignment') {
      return 'Internship requirement';
    }
    return switch (user.role) {
      UserRole.coordinator => 'Student intern',
      UserRole.student => 'Program Coordinator',
      UserRole.admin => 'Assigned account',
    };
  }
}

IconData _noticeIcon(String type) => switch (type) {
  'document_feedback' || 'document_submission' => Icons.description_outlined,
  'deadline' => Icons.event_outlined,
  'verification_reminder' => Icons.fact_check_outlined,
  'status_update' => Icons.track_changes_outlined,
  'dtr_submission' || 'dtr_update' => Icons.punch_clock_outlined,
  'assignment' => Icons.group_add_outlined,
  'evaluation' => Icons.assignment_turned_in_outlined,
  _ => Icons.notifications_outlined,
};

String _typeLabel(String type) => switch (type) {
  'document_feedback' => 'Document Feedback',
  'document_submission' => 'Document Submission',
  'deadline' => 'Deadline',
  'verification_reminder' => 'Verification reminder',
  'status_update' => 'Status Update',
  'dtr_submission' => 'DTR Submission',
  'dtr_update' => 'DTR Update',
  'assignment' => 'Assignment',
  'evaluation' => 'Evaluation',
  _ => 'General',
};
