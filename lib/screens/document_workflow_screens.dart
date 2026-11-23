import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/cas_programs.dart';
import '../models/records.dart';
import '../models/workflow_models.dart';
import '../services/practicum_repository.dart';
import 'workflow_shared.dart';
import 'pdf_template_widgets.dart';
import 'repository_directory.dart';
import 'workspace_select_field.dart';

class StudentStatusTrackerScreen extends StatelessWidget {
  const StudentStatusTrackerScreen({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Status Tracker',
    subtitle:
        'Track requirements, verification, deployment, internship progress, completion, and archiving.',
    eyebrow: 'My Internship  ›  Status Tracker',
    child: StreamBuilder<List<RequirementDefinition>>(
      stream: repository.watchRequirementDefinitions(),
      builder: (context, definitionSnapshot) => StreamBuilder<List<RequirementRecord>>(
        stream: repository.watchRequirements(user),
        builder: (context, recordSnapshot) {
          final definitions =
              (definitionSnapshot.data ?? const <RequirementDefinition>[])
                  .where(
                    (definition) => definition.appliesToProgram(user.program),
                  )
                  .toList();
          final records = recordSnapshot.data ?? const <RequirementRecord>[];
          final items = definitions.isEmpty
              ? records
                    .map(
                      (record) => _TrackerItem(
                        title: record.title,
                        dueDate: record.dueDate,
                        record: record,
                      ),
                    )
                    .toList()
              : definitions.map((definition) {
                  final matches =
                      records
                          .where(
                            (record) =>
                                record.definitionId == definition.id ||
                                record.title.toLowerCase() ==
                                    definition.title.toLowerCase(),
                          )
                          .toList()
                        ..sort(
                          (a, b) => b.submittedAt.compareTo(a.submittedAt),
                        );
                  return _TrackerItem(
                    title: definition.title,
                    dueDate: definition.dueDate,
                    record: matches.firstOrNull,
                  );
                }).toList();

          return StreamBuilder<InternshipProfileRecord?>(
            stream: repository.watchInternshipProfile(user.uid),
            builder: (context, profileSnapshot) {
              final stage =
                  profileSnapshot.data?.stage ??
                  InternshipStage.pendingRequirements;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InternshipStageProgress(stage: stage),
                  const SizedBox(height: 8),
                  StreamBuilder<List<String>>(
                    stream: repository.watchStudentEvaluationStatuses(
                      user.uid,
                      user.academicYear,
                    ),
                    builder: (context, evaluationSnapshot) {
                      final statuses =
                          evaluationSnapshot.data ?? const <String>[];

                      final statusText =
                          user.academicYear == null ||
                              user.academicYear!.trim().isEmpty
                          ? 'Academic year is not set. Ask your coordinator to check your internship profile.'
                          : evaluationSnapshot.hasError
                          ? 'Evaluation status is temporarily unavailable.'
                          : !evaluationSnapshot.hasData
                          ? 'Checking evaluation statuses...'
                          : statuses.isEmpty
                          ? 'No evaluation status recorded for this academic year yet. If your supervisor already submitted an evaluation, ask your coordinator to confirm.'
                          : statuses
                                .asMap()
                                .entries
                                .map((entry) {
                                  final label = entry.value == 'submitted'
                                      ? 'Submitted'
                                      : 'Pending';
                                  return 'Evaluation ${entry.key + 1}: $label';
                                })
                                .join('\n');
                      return SectionCard(
                        title: 'Supervisor Evaluations',
                        subtitle:
                            'Submission status only. Ratings and comments are confidential.',
                        child: Text(statusText),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final main = _TrackerList(
                          items: items,
                          repository: repository,
                        );
                        final side = _StudentTrackerSide(
                          user: user,
                          items: items,
                        );
                        if (constraints.maxWidth < 920) {
                          return ListView(
                            children: [main, const SizedBox(height: 12), side],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: SingleChildScrollView(child: main),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 340,
                              child: SingleChildScrollView(child: side),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );
}

class _InternshipStageProgress extends StatelessWidget {
  const _InternshipStageProgress({required this.stage});

  final InternshipStage stage;

  @override
  Widget build(BuildContext context) {
    const stages = InternshipStage.values;
    final currentIndex = stages.indexOf(stage);
    return SectionCard(
      title: 'Internship Progress',
      subtitle: 'Current stage: ${stage.label}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 960;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < stages.length; index++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          index < currentIndex
                              ? Icons.check_circle
                              : index == currentIndex
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: index <= currentIndex
                              ? AppTheme.blue
                              : AppTheme.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            stages[index].label,
                            style: TextStyle(
                              fontSize: AppTheme.fontSmall,
                              color: index == currentIndex
                                  ? AppTheme.deepBlue
                                  : AppTheme.muted,
                              fontWeight: index == currentIndex
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }
          return Row(
            children: [
              for (var index = 0; index < stages.length; index++) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index <= currentIndex
                              ? AppTheme.blue
                              : AppTheme.border,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          index < currentIndex
                              ? Icons.check_rounded
                              : index == currentIndex
                              ? Icons.circle
                              : Icons.circle_outlined,
                          size: index == currentIndex ? 10 : 15,
                          color: index <= currentIndex
                              ? Colors.white
                              : AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        stages[index].label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTheme.fontCaption,
                          fontWeight: index == currentIndex
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: index <= currentIndex
                              ? AppTheme.text
                              : AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < stages.length - 1)
                  Container(
                    width: 18,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 28),
                    color: index < currentIndex
                        ? AppTheme.blue
                        : AppTheme.border,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TrackerItem {
  const _TrackerItem({
    required this.title,
    required this.dueDate,
    required this.record,
  });

  final String title;
  final DateTime? dueDate;
  final RequirementRecord? record;
}

class _TrackerList extends StatelessWidget {
  const _TrackerList({required this.items, required this.repository});
  final List<_TrackerItem> items;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SectionCard(
        child: EmptyWorkflowState(
          icon: Icons.track_changes_outlined,
          title: 'No requirements configured',
          message: 'Your coordinator has not configured submission bins yet.',
        ),
      );
    }
    return Column(
      children: items.map((item) {
        final record = item.record;
        return Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: AppTheme.muted,
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
                                item.title,
                                style: const TextStyle(
                                  fontSize: AppTheme.fontSmall,
                                  color: AppTheme.text,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            StatusBadge(
                              record?.status.label ?? 'Not submitted',
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          record == null
                              ? 'Due ${shortDate(item.dueDate)}'
                              : 'Submitted on ${shortDate(record.submittedAt)}',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: AppTheme.fontCaption,
                          ),
                        ),
                        if (record?.remarks?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.chat_bubble_outline,
                                size: 13,
                                color: AppTheme.muted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Feedback from Coordinator\n${record!.remarks}',
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: AppTheme.fontCaption,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (record?.storagePath != null)
                    IconButton(
                      tooltip: 'Open document',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => openStorageDocument(
                        context,
                        repository,
                        record!.storagePath,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 17),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StudentTrackerSide extends StatelessWidget {
  const _StudentTrackerSide({required this.user, required this.items});
  final AppUser user;
  final List<_TrackerItem> items;

  @override
  Widget build(BuildContext context) {
    final upcoming =
        items
            .where(
              (item) =>
                  item.dueDate != null && item.dueDate!.isAfter(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
    return Column(
      children: [
        SectionCard(
          title: 'Student Information',
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.surfaceSoft,
                    foregroundColor: AppTheme.muted,
                    child: Text(
                      user.displayName.isEmpty
                          ? '?'
                          : user.displayName.substring(0, 1).toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: const TextStyle(
                            fontSize: AppTheme.fontSmall,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          user.studentNumber ?? 'No student number',
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: AppTheme.fontCaption,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              InfoRow('Program', user.program ?? 'Not set', labelWidth: 72),
              InfoRow(
                'Year Level',
                user.yearLevel ?? 'Not set',
                labelWidth: 72,
              ),
              InfoRow('Email', user.email, labelWidth: 72),
              InfoRow(
                'Adviser',
                user.coordinatorName ?? 'Unassigned',
                labelWidth: 72,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Document Deadlines',
          child: upcoming.isEmpty
              ? const Text(
                  'No upcoming deadlines.',
                  style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.muted,
                  ),
                )
              : Column(
                  children: upcoming.take(6).map((item) {
                    final days = item.dueDate!
                        .difference(DateTime.now())
                        .inDays;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_outlined,
                            size: 15,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: AppTheme.fontCaption,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  shortDate(item.dueDate),
                                  style: const TextStyle(
                                    fontSize: AppTheme.fontCaption,
                                    color: AppTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            days <= 0 ? 'Due' : '$days days left',
                            style: TextStyle(
                              color: days <= 3
                                  ? AppTheme.danger
                                  : AppTheme.muted,
                              fontSize: AppTheme.fontCaption,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceSoft,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: AppTheme.muted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Submit your documents on or before the deadline to avoid delays in your internship clearance.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: AppTheme.fontCaption,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class StudentRequirementsChecklistScreen extends StatefulWidget {
  const StudentRequirementsChecklistScreen({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final PracticumRepository repository;

  @override
  State<StudentRequirementsChecklistScreen> createState() =>
      _StudentRequirementsChecklistScreenState();
}

class _StudentRequirementsChecklistScreenState
    extends State<StudentRequirementsChecklistScreen> {
  String _query = '';
  String _filter = 'All Requirements';
  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Requirements Checklist',
    subtitle:
        'Track required documents, deadlines, and review status. Upload and preview files in the Document Submission Bin.',
    eyebrow: 'My Internship  ›  Requirements Checklist',
    child: StreamBuilder<List<RequirementDefinition>>(
      stream: widget.repository.watchRequirementDefinitions(),
      builder: (context, definitionSnapshot) => StreamBuilder<List<RequirementRecord>>(
        stream: widget.repository.watchRequirements(widget.user),
        builder: (context, recordSnapshot) {
          final records = recordSnapshot.data ?? const <RequirementRecord>[];
          final definitions =
              (definitionSnapshot.data ?? const <RequirementDefinition>[])
                  .where(
                    (definition) =>
                        definition.active &&
                        definition.appliesToProgram(widget.user.program),
                  )
                  .toList()
                ..sort((a, b) {
                  final order = a.sortOrder.compareTo(b.sortOrder);
                  if (order != 0) return order;
                  return a.dueDate.compareTo(b.dueDate);
                });

          final items = definitions.map((definition) {
            final matches =
                records
                    .where(
                      (record) =>
                          record.definitionId == definition.id ||
                          record.title.toLowerCase() ==
                              definition.title.toLowerCase(),
                    )
                    .toList()
                  ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
            return _RequirementChecklistItem(
              definition: definition,
              record: matches.firstOrNull,
            );
          }).toList();

          final completed = items
              .where((item) => item.record?.status == ReviewStatus.verified)
              .length;
          final needsAttention = items.where((item) {
            final status = item.record?.status;
            return item.record == null ||
                status == ReviewStatus.needsRevision ||
                status == ReviewStatus.rejected;
          }).length;
          final upcoming = items
              .where(
                (item) =>
                    item.definition.dueDate.isAfter(DateTime.now()) &&
                    item.record?.status != ReviewStatus.verified,
              )
              .length;

          final visible = items.where((item) {
            final haystack =
                '${item.definition.title} ${item.definition.description} ${item.definition.category}'
                    .toLowerCase();
            final queryMatches =
                _query.isEmpty || haystack.contains(_query.toLowerCase());
            final status = item.record?.status;
            final filterMatches = switch (_filter) {
              'Completed' => status == ReviewStatus.verified,
              'Needs Attention' =>
                item.record == null ||
                    status == ReviewStatus.needsRevision ||
                    status == ReviewStatus.rejected,
              'Submitted' => item.record != null,
              _ => true,
            };
            return queryMatches && filterMatches;
          }).toList();

          return ListView(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 900
                      ? 4
                      : width >= 560
                      ? 2
                      : 1;
                  final cardWidth = columns == 1
                      ? width
                      : (width - ((columns - 1) * 10)) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ChecklistSummaryCard(
                        width: cardWidth,
                        icon: Icons.fact_check_outlined,
                        label: 'Total Requirements',
                        value: '${items.length}',
                      ),
                      _ChecklistSummaryCard(
                        width: cardWidth,
                        icon: Icons.verified_outlined,
                        label: 'Completed',
                        value: '$completed',
                        accent: AppTheme.success,
                      ),
                      _ChecklistSummaryCard(
                        width: cardWidth,
                        icon: Icons.priority_high_rounded,
                        label: 'Needs Attention',
                        value: '$needsAttention',
                        accent: AppTheme.warning,
                      ),
                      _ChecklistSummaryCard(
                        width: cardWidth,
                        icon: Icons.event_outlined,
                        label: 'Upcoming',
                        value: '$upcoming',
                        accent: AppTheme.purple,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 310,
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded, size: 18),
                            hintText: 'Search requirements…',
                          ),
                          onChanged: (value) => setState(() => _query = value),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: WorkspaceSelectField(
                          label: 'Checklist Status',
                          initialValue: _filter,
                          options: const [
                            'All Requirements',
                            'Completed',
                            'Submitted',
                            'Needs Attention',
                          ],
                          onChanged: (value) => setState(() => _filter = value),
                        ),
                      ),
                      if (widget.user.program?.isNotEmpty == true)
                        Text(
                          widget.user.program!,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: AppTheme.fontSmall,
                          ),
                        ),
                      if (widget.user.academicYear?.isNotEmpty == true)
                        Text(
                          widget.user.academicYear!,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: AppTheme.fontSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const EmptyWorkflowState(
                  icon: Icons.fact_check_outlined,
                  title: 'No matching requirements',
                  message:
                      'Try another filter, or contact your coordinator if your checklist is empty.',
                )
              else
                ...visible.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequirementChecklistTile(item: item),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class _RequirementChecklistItem {
  const _RequirementChecklistItem({
    required this.definition,
    required this.record,
  });

  final RequirementDefinition definition;
  final RequirementRecord? record;
}

class _ChecklistSummaryCard extends StatelessWidget {
  const _ChecklistSummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    this.accent = AppTheme.blue,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: AppTheme.fontSmall,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RequirementChecklistTile extends StatelessWidget {
  const _RequirementChecklistTile({required this.item});

  final _RequirementChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final definition = item.definition;
    final record = item.record;
    final statusLabel = _studentRequirementStatusLabel(record);
    final completed = record?.status == ReviewStatus.verified;
    final needsAttention =
        record == null ||
        record.status == ReviewStatus.needsRevision ||
        record.status == ReviewStatus.rejected;
    final indicator = completed
        ? AppTheme.success
        : needsAttention
        ? AppTheme.warning
        : AppTheme.blue;
    final icon = completed
        ? Icons.check_circle_outline_rounded
        : needsAttention
        ? Icons.assignment_late_outlined
        : Icons.hourglass_top_rounded;
    final description = definition.description.trim().isNotEmpty
        ? definition.description.trim()
        : definition.instructions.trim().isNotEmpty
        ? definition.instructions.trim()
        : 'Details unavailable.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: indicator.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: indicator, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 9,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        definition.title.trim().isEmpty
                            ? 'Requirement unavailable'
                            : definition.title.trim(),
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: AppTheme.fontBody,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      StatusBadge(
                        statusLabel,
                        compact: true,
                        fontSize: AppTheme.fontSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: AppTheme.fontSmall,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 16,
                    runSpacing: 7,
                    children: [
                      _ChecklistMeta(
                        icon: Icons.event_outlined,
                        text: 'Due ${shortDate(definition.dueDate)}',
                      ),
                      if (definition.category.trim().isNotEmpty)
                        _ChecklistMeta(
                          icon: Icons.folder_outlined,
                          text: definition.category.trim(),
                        ),
                      if (record != null)
                        _ChecklistMeta(
                          icon: Icons.history_rounded,
                          text:
                              'Submitted ${DateFormat.MMMd().format(record.submittedAt)}',
                        ),
                    ],
                  ),
                  if (definition.instructions.trim().isNotEmpty &&
                      definition.instructions.trim() != description) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Instructions: ${definition.instructions.trim()}',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: AppTheme.fontSmall,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (record?.remarks?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: AppTheme.muted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              'Coordinator feedback: ${record!.remarks!.trim()}',
                              style: const TextStyle(
                                color: AppTheme.text,
                                fontSize: AppTheme.fontSmall,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
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
}

class _ChecklistMeta extends StatelessWidget {
  const _ChecklistMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: AppTheme.muted),
      const SizedBox(width: 4),
      Text(
        text,
        style: const TextStyle(
          color: AppTheme.muted,
          fontSize: AppTheme.fontSmall,
        ),
      ),
    ],
  );
}

String _studentRequirementStatusLabel(
  RequirementRecord? record, {
  bool locallySubmitted = false,
}) {
  if (locallySubmitted && record?.status != ReviewStatus.pending) {
    return 'Submitted';
  }
  if (record == null) return 'Not submitted';
  if (record.status == ReviewStatus.pending) return 'Submitted';
  return record.status.label;
}

class DocumentSubmissionBinScreen extends StatefulWidget {
  const DocumentSubmissionBinScreen({
    super.key,
    required this.user,
    required this.repository,
    this.initialDefinitionId,
  });
  final AppUser user;
  final PracticumRepository repository;
  final String? initialDefinitionId;

  @override
  State<DocumentSubmissionBinScreen> createState() =>
      _DocumentSubmissionBinScreenState();
}

class _DocumentSubmissionBinScreenState
    extends State<DocumentSubmissionBinScreen> {
  String _query = '';
  String _status = 'All Statuses';
  String _category = 'All Document Types';
  RequirementDefinition? _selected;
  final Set<String> _locallySubmittedDefinitions = {};

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Document Submission Bin',
    subtitle:
        'View instructions, download forms, and upload required documents.',
    eyebrow: 'Home  ›  Document Submission Bin',
    actions: [
      OutlinedButton.icon(
        icon: const Icon(Icons.folder_open_rounded),
        label: const Text('My documents'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('My documents')),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DocumentRepositoryScreen(
                    user: widget.user,
                    repository: widget.repository,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
    child: StreamBuilder<List<RequirementDefinition>>(
      stream: widget.repository.watchRequirementDefinitions(),
      builder: (context, definitionSnapshot) => StreamBuilder<List<RequirementRecord>>(
        stream: widget.repository.watchRequirements(widget.user),
        builder: (context, recordSnapshot) {
          if (definitionSnapshot.hasError || recordSnapshot.hasError) {
            return const EmptyWorkflowState(
              icon: Icons.inbox_outlined,
              title: 'Submission data unavailable',
              message:
                  'Required documents are unavailable right now. Please try again later.',
            );
          }
          if (!definitionSnapshot.hasData || !recordSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = recordSnapshot.data!;
          final allDefinitions = definitionSnapshot.data!
              .where(
                (definition) =>
                    definition.active &&
                    definition.appliesToProgram(widget.user.program),
              )
              .toList();
          final confirmedSubmissions = _locallySubmittedDefinitions.where((id) {
            final definition = allDefinitions
                .where((item) => item.id == id)
                .firstOrNull;
            return definition != null &&
                _recordFor(definition, records)?.status == ReviewStatus.pending;
          }).toSet();
          if (confirmedSubmissions.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(
                  () => _locallySubmittedDefinitions.removeAll(
                    confirmedSubmissions,
                  ),
                );
              }
            });
          }
          final categories = {
            'All Document Types',
            ...allDefinitions.map((definition) => definition.category),
          }.toList();
          final categoryFilter = categories.contains(_category)
              ? _category
              : 'All Document Types';
          final definitions = allDefinitions.where((definition) {
            final record = _recordFor(definition, records);
            final locallySubmitted = _locallySubmittedDefinitions.contains(
              definition.id,
            );
            final matchesQuery =
                _query.isEmpty ||
                '${definition.title} ${definition.description}'
                    .toLowerCase()
                    .contains(_query);
            final matchesStatus =
                _status == 'All Statuses' ||
                (_status == 'Not submitted'
                    ? record == null && !locallySubmitted
                    : _studentRequirementStatusLabel(
                            record,
                            locallySubmitted: locallySubmitted,
                          ) ==
                          _status);
            final matchesCategory =
                categoryFilter == 'All Document Types' ||
                definition.category == categoryFilter;
            return matchesQuery && matchesStatus && matchesCategory;
          }).toList();
          final initialDefinitionId = widget.initialDefinitionId;
          final selected =
              _selected != null &&
                  definitions.any((item) => item.id == _selected!.id)
              ? definitions.firstWhere((item) => item.id == _selected!.id)
              : initialDefinitionId != null &&
                    definitions.any((item) => item.id == initialDefinitionId)
              ? definitions.firstWhere((item) => item.id == initialDefinitionId)
              : definitions.firstOrNull;
          final selectedRecord = selected == null
              ? null
              : _recordFor(selected, records);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    child: TextField(
                      style: const TextStyle(fontSize: AppTheme.fontBody),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 18),
                        hintText: 'Search documents…',
                        hintStyle: TextStyle(fontSize: AppTheme.fontBody),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.toLowerCase()),
                    ),
                  ),
                  _filterBox(
                    width: 160,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Academic Year',
                        labelStyle: TextStyle(fontSize: AppTheme.fontSmall),
                      ),
                      child: Text(
                        widget.user.academicYear?.trim().isNotEmpty == true
                            ? widget.user.academicYear!.trim()
                            : 'Unavailable',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppTheme.fontBody),
                      ),
                    ),
                  ),
                  _filterBox(
                    width: 180,
                    child: WorkspaceSelectField(
                      key: ValueKey(categoryFilter),
                      label: 'Document Type',
                      initialValue: categoryFilter,
                      options: categories,
                      optionLabel: (value) =>
                          value == 'All Document Types' ? 'All types' : value,
                      onChanged: (value) => setState(() => _category = value),
                    ),
                  ),
                  _filterBox(
                    width: 160,
                    child: WorkspaceSelectField(
                      label: 'Status',
                      initialValue: _status,
                      options: const [
                        'All Statuses',
                        'Not submitted',
                        'Submitted',
                        'Under review',
                        'Verified',
                        'Needs revision',
                        'Rejected',
                      ],
                      onChanged: (value) => setState(() => _status = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final grid = _SubmissionGrid(
                      definitions: definitions,
                      records: records,
                      locallySubmittedDefinitions: _locallySubmittedDefinitions,
                      selected: selected,
                      onSelect: (value) => setState(() => _selected = value),
                    );
                    final detail = selected == null
                        ? EmptyWorkflowState(
                            icon: Icons.inbox_outlined,
                            title: allDefinitions.isEmpty
                                ? 'No submission bins'
                                : 'No matching requirements',
                            message: allDefinitions.isEmpty
                                ? 'Ask the coordinator to configure requirements.'
                                : 'Adjust the filters to see other requirements.',
                          )
                        : _SubmissionDetail(
                            definition: selected,
                            allDefinitions: allDefinitions,
                            record: selectedRecord,
                            user: widget.user,
                            repository: widget.repository,
                            locallySubmitted: _locallySubmittedDefinitions
                                .contains(selected.id),
                            onSubmitted: (definitionId) => setState(
                              () => _locallySubmittedDefinitions.add(
                                definitionId,
                              ),
                            ),
                          );
                    if (constraints.maxWidth < 960) {
                      return ListView(
                        children: [
                          SizedBox(height: 360, child: grid),
                          const SizedBox(height: 12),
                          detail,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 7, child: grid),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 400,
                          child: SingleChildScrollView(child: detail),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _filterBox({required double width, required Widget child}) =>
      SizedBox(width: width, child: child);

  RequirementRecord? _recordFor(
    RequirementDefinition definition,
    List<RequirementRecord> records,
  ) {
    final matches =
        records
            .where(
              (record) =>
                  record.definitionId == definition.id ||
                  record.title.toLowerCase() == definition.title.toLowerCase(),
            )
            .toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return matches.firstOrNull;
  }
}

class _SubmissionGrid extends StatelessWidget {
  const _SubmissionGrid({
    required this.definitions,
    required this.records,
    required this.locallySubmittedDefinitions,
    required this.selected,
    required this.onSelect,
  });

  final List<RequirementDefinition> definitions;
  final List<RequirementRecord> records;
  final Set<String> locallySubmittedDefinitions;
  final RequirementDefinition? selected;
  final ValueChanged<RequirementDefinition> onSelect;

  @override
  Widget build(BuildContext context) {
    if (definitions.isEmpty) {
      return const EmptyWorkflowState(
        icon: Icons.inbox_outlined,
        title: 'No matching requirements',
        message: 'Adjust the filters or contact your coordinator.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView.separated(
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemCount: definitions.length,
          itemBuilder: (context, index) {
            final definition = definitions[index];
            final matches =
                records
                    .where(
                      (record) =>
                          record.definitionId == definition.id ||
                          record.title.toLowerCase() ==
                              definition.title.toLowerCase(),
                    )
                    .toList()
                  ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
            final record = matches.firstOrNull;
            final locallySubmitted = locallySubmittedDefinitions.contains(
              definition.id,
            );
            final active = selected?.id == definition.id;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(definition),
              child: Card(
                color: active ? AppTheme.surfaceBlue : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: active ? AppTheme.blue : AppTheme.border,
                    width: active ? 1.4 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        definition.title.trim().isEmpty
                            ? 'Unavailable'
                            : definition.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Due: ${shortDate(definition.dueDate)}',
                        style: const TextStyle(
                          fontSize: AppTheme.fontSmall,
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        definition.description.trim().isEmpty
                            ? 'Unavailable'
                            : definition.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: AppTheme.fontBody,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StatusBadge(
                        _studentRequirementStatusLabel(
                          record,
                          locallySubmitted: locallySubmitted,
                        ),
                        compact: true,
                        fontSize: AppTheme.fontSmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SubmissionDetail extends StatelessWidget {
  const _SubmissionDetail({
    required this.definition,
    required this.allDefinitions,
    required this.record,
    required this.user,
    required this.repository,
    required this.locallySubmitted,
    required this.onSubmitted,
  });

  final RequirementDefinition definition;
  final List<RequirementDefinition> allDefinitions;
  final RequirementRecord? record;
  final AppUser user;
  final PracticumRepository repository;
  final bool locallySubmitted;
  final ValueChanged<String> onSubmitted;

  List<RequirementDefinition> get _upcomingDefinitions =>
      allDefinitions
          .where(
            (item) =>
                item.dueDate.isAfter(DateTime.now()) &&
                item.id != definition.id,
          )
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SectionCard(
        title: definition.title.trim().isEmpty
            ? 'Unavailable'
            : definition.title,
        trailing: StatusBadge(
          _studentRequirementStatusLabel(
            record,
            locallySubmitted: locallySubmitted,
          ),
          compact: true,
          fontSize: AppTheme.fontSmall,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Due Date: ${shortDate(definition.dueDate)}',
              style: const TextStyle(
                fontSize: AppTheme.fontSmall,
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Instructions',
              style: TextStyle(
                fontSize: AppTheme.fontBody,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              definition.instructions.trim().isNotEmpty
                  ? definition.instructions
                  : definition.description.trim().isNotEmpty
                  ? definition.description
                  : 'Unavailable',
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: AppTheme.fontBody,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            if (definition.pdfTemplate != null)
              PdfTemplateActions(
                key: ValueKey(definition.id),
                template: definition.pdfTemplate!,
                repository: repository,
                user: user,
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          definition.officialFormUrl?.trim().isNotEmpty == true
                          ? () => _openUrl(definition.officialFormUrl!.trim())
                          : null,
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: Text(
                        definition.officialFormUrl?.trim().isNotEmpty == true
                            ? 'Download Official Form'
                            : 'Unavailable',
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          definition.sampleFormUrl?.trim().isNotEmpty == true
                          ? () => _openUrl(definition.sampleFormUrl!.trim())
                          : null,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(
                        definition.sampleFormUrl?.trim().isNotEmpty == true
                            ? 'View Sample Form'
                            : 'Unavailable',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            _SubmissionUploadPanel(
              definition: definition,
              record: record,
              user: user,
              repository: repository,
              locallySubmitted: locallySubmitted,
              onSubmitted: onSubmitted,
            ),
          ],
        ),
      ),
      if (record != null) ...[
        const SizedBox(height: 10),
        SectionCard(
          title: 'Submission History',
          child: ListTile(
            dense: false,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Version ${record!.version}',
              style: const TextStyle(
                fontSize: AppTheme.fontBody,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Submitted by ${record!.studentName.trim().isEmpty ? 'Unavailable' : record!.studentName}\n'
              '${DateFormat.yMMMd().add_jm().format(record!.submittedAt)}\n'
              'File: ${record!.fileName?.trim().isNotEmpty == true ? record!.fileName!.trim() : 'Unavailable'}',
              style: const TextStyle(fontSize: AppTheme.fontSmall, height: 1.4),
            ),
            trailing: StatusBadge(
              _studentRequirementStatusLabel(record),
              compact: true,
              fontSize: AppTheme.fontSmall,
            ),
            onTap: record!.storagePath?.trim().isNotEmpty == true
                ? () => openStorageDocument(
                    context,
                    repository,
                    record!.storagePath,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Coordinator Feedback',
          child: Text(
            record!.remarks?.trim().isNotEmpty == true
                ? record!.remarks!.trim()
                : 'No feedback yet.',
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: AppTheme.fontBody,
              height: 1.5,
            ),
          ),
        ),
      ] else ...[
        const SizedBox(height: 10),
        const SectionCard(
          title: 'Submission History',
          child: Text('No submissions yet.'),
        ),
        const SizedBox(height: 10),
        const SectionCard(
          title: 'Coordinator Feedback',
          child: Text('Unavailable until the first submission is reviewed.'),
        ),
      ],
      const SizedBox(height: 10),
      SectionCard(
        title: 'Upcoming Deadlines',
        trailing: TextButton(
          onPressed: () => _showAllDeadlines(context),
          child: const Text('View All'),
        ),
        child: _upcomingDefinitions.isEmpty
            ? const Text('No upcoming deadlines.')
            : Column(
                children: _upcomingDefinitions
                    .take(4)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceSoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                DateFormat(
                                  'MMM\ndd',
                                ).format(item.dueDate).toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: AppTheme.fontSmall,
                                  height: 1.15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.title.trim().isEmpty
                                    ? 'Unavailable'
                                    : item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: AppTheme.fontSmall,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );

  Future<void> _showAllDeadlines(BuildContext context) async {
    final upcoming =
        allDefinitions
            .where((item) => item.dueDate.isAfter(DateTime.now()))
            .toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Upcoming Deadlines'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: upcoming.isEmpty
              ? const Center(child: Text('No upcoming deadlines.'))
              : ListView.separated(
                  itemCount: upcoming.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = upcoming[index];
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          DateFormat(
                            'MMM\ndd',
                          ).format(item.dueDate).toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: AppTheme.fontSmall,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(item.title),
                      subtitle: Text(item.description),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String value) async {
    await launchUrl(
      Uri.parse(value),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  }
}

class _SubmissionUploadPanel extends StatefulWidget {
  const _SubmissionUploadPanel({
    required this.definition,
    required this.record,
    required this.user,
    required this.repository,
    required this.locallySubmitted,
    required this.onSubmitted,
  });

  final RequirementDefinition definition;
  final RequirementRecord? record;
  final AppUser user;
  final PracticumRepository repository;
  final bool locallySubmitted;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SubmissionUploadPanel> createState() => _SubmissionUploadPanelState();
}

class _SubmissionUploadPanelState extends State<_SubmissionUploadPanel> {
  static const _allowedExtensions = {
    'pdf',
    'doc',
    'docx',
    'png',
    'jpg',
    'jpeg',
  };
  static const _maxFileSize = 5 * 1024 * 1024;

  DropzoneViewController? _dropzoneController;
  PlatformFile? _stagedFile;
  Uint8List? _stagedBytes;
  bool _loadingFile = false;
  bool _submitting = false;
  bool _dragging = false;
  String? _errorMessage;
  String? _successMessage;

  bool get _canUpload {
    if (_submitting || _loadingFile) return false;
    if (widget.record == null) return !widget.locallySubmitted;
    return {
      ReviewStatus.needsRevision,
      ReviewStatus.rejected,
    }.contains(widget.record!.status);
  }

  @override
  void didUpdateWidget(covariant _SubmissionUploadPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition.id != widget.definition.id) {
      _stagedFile = null;
      _stagedBytes = null;
      _errorMessage = null;
      _successMessage = null;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Upload Your Document',
        style: TextStyle(
          fontSize: AppTheme.fontBody,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 7),
      if (_submitting)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceBlue,
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(
            children: [
              SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Uploading your document…',
                  style: TextStyle(
                    fontSize: AppTheme.fontBody,
                    color: AppTheme.navy,
                  ),
                ),
              ),
            ],
          ),
        )
      else if (!_canUpload && _stagedFile == null)
        _messageCard(
          icon: Icons.hourglass_top_rounded,
          message:
              widget.locallySubmitted ||
                  widget.record?.status == ReviewStatus.pending ||
                  widget.record?.status == ReviewStatus.underReview
              ? 'Your document is submitted and waiting for coordinator review.'
              : 'You can upload a corrected file when your coordinator requests a revision.',
          color: AppTheme.sky,
        )
      else if (_stagedFile != null)
        _stagedFileCard()
      else ...[
        _dropArea(),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: _canUpload ? _chooseFile : null,
          icon: const Icon(Icons.attach_file, size: 17),
          label: Text(_loadingFile ? 'Preparing file…' : 'Choose file'),
        ),
        const SizedBox(height: 5),
        const Text(
          'PDF, Word, PNG or JPG • Max file size: 5 MB',
          style: TextStyle(fontSize: AppTheme.fontSmall, color: AppTheme.muted),
        ),
      ],
      if (_errorMessage != null) ...[
        const SizedBox(height: 8),
        _messageCard(
          icon: Icons.error_outline,
          message: _errorMessage!,
          color: const Color(0xFFFFF2F0),
          textColor: AppTheme.danger,
        ),
      ],
      if (_successMessage != null) ...[
        const SizedBox(height: 8),
        _messageCard(
          icon: Icons.check_circle_outline,
          message: _successMessage!,
          color: const Color(0xFFEDF8F2),
          textColor: AppTheme.success,
        ),
      ],
    ],
  );

  Widget _dropArea() => Container(
    height: 105,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _dragging ? AppTheme.sky : AppTheme.surface,
      border: Border.all(
        color: _dragging ? AppTheme.blue : AppTheme.borderStrong,
        width: _dragging ? 1.5 : 1,
      ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Stack(
      children: [
        if (kIsWeb)
          Positioned.fill(
            child: DropzoneView(
              operation: DragOperation.copy,
              cursor: CursorType.copy,
              onCreated: (controller) => _dropzoneController = controller,
              onHover: () {
                if (mounted) setState(() => _dragging = true);
              },
              onLeave: () {
                if (mounted) setState(() => _dragging = false);
              },
              onDropFile: (file) {
                if (mounted) {
                  setState(() => _dragging = false);
                  unawaited(_handleDroppedFile(file));
                }
              },
              onDropInvalid: (_) {
                if (mounted) {
                  setState(() {
                    _dragging = false;
                    _errorMessage = 'Choose a PDF, Word, PNG or JPG file.';
                  });
                }
              },
              onError: (error) {
                if (mounted && error != null) {
                  setState(
                    () => _errorMessage = 'Could not read the dropped file.',
                  );
                }
              },
            ),
          ),
        IgnorePointer(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  color: _dragging ? AppTheme.deepBlue : AppTheme.blue,
                  size: 30,
                ),
                const SizedBox(height: 5),
                Text(
                  kIsWeb ? 'Drop your file here' : 'Choose a file to stage',
                  style: const TextStyle(
                    fontSize: AppTheme.fontBody,
                    color: AppTheme.muted,
                  ),
                ),
                if (kIsWeb)
                  const Text(
                    'You can also use the Choose file button below',
                    style: TextStyle(
                      fontSize: AppTheme.fontSmall,
                      color: AppTheme.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _stagedFileCard() {
    final file = _stagedFile!;
    final size = _stagedBytes?.length ?? file.lengthSync() ?? 0;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlue,
        border: Border.all(color: AppTheme.borderStrong),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.insert_drive_file_outlined,
                color: AppTheme.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTheme.fontSmall,
                        color: AppTheme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatFileSize(size)} • Ready to review',
                      style: const TextStyle(
                        fontSize: AppTheme.fontSmall,
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _chooseFile,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('Replace'),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _reviewAndSubmit,
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Review & submit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required String message,
    required Color color,
    Color textColor = AppTheme.navy,
  }) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: textColor),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: AppTheme.fontSmall,
              color: textColor,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _chooseFile() async {
    if (!_canUpload) return;
    setState(() {
      _loadingFile = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Choose an internship document',
        type: FileType.custom,
        allowedExtensions: _allowedExtensions.toList(),
      );
      if (file != null) await _stageFile(file);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = '$error');
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  Future<void> _handleDroppedFile(DropzoneFileInterface droppedFile) async {
    final controller = _dropzoneController;
    if (controller == null || !_canUpload) return;
    setState(() {
      _loadingFile = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final name = await controller.getFilename(droppedFile);
      final extension = name.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(extension)) {
        if (mounted) {
          setState(
            () => _errorMessage = 'Choose a PDF, Word, PNG or JPG file.',
          );
        }
        return;
      }
      final size = await controller.getFileSize(droppedFile);
      if (size > _maxFileSize) {
        if (mounted) {
          setState(
            () => _errorMessage = 'The file exceeds the 5 MB size limit.',
          );
        }
        return;
      }
      final bytes = await controller.getFileData(droppedFile);
      await _stageFile(_DroppedDocumentPlatformFile(name, bytes));
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Could not read the dropped file: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingFile = false);
    }
  }

  Future<void> _stageFile(PlatformFile file) async {
    final extension = file.extension?.toLowerCase() ?? '';
    if (!_allowedExtensions.contains(extension)) {
      if (mounted) {
        setState(() => _errorMessage = 'Choose a PDF, Word, PNG or JPG file.');
      }
      return;
    }

    final size = await file.length();
    if (size != null && size > _maxFileSize) {
      if (mounted) {
        setState(() => _errorMessage = 'The file exceeds the 5 MB size limit.');
      }
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      if (mounted) {
        setState(() => _errorMessage = 'The selected file is empty.');
      }
      return;
    }
    if (bytes.length > _maxFileSize) {
      if (mounted) {
        setState(() => _errorMessage = 'The file exceeds the 5 MB size limit.');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _stagedFile = file;
      _stagedBytes = bytes;
      _loadingFile = false;
      _errorMessage = null;
    });
    await _reviewAndSubmit();
  }

  Future<void> _reviewAndSubmit() async {
    final file = _stagedFile;
    final bytes = _stagedBytes;
    if (file == null || bytes == null || !_canUpload) return;
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
          child: SizedBox(
            width: 780,
            height: 620,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        color: AppTheme.blue,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Review your document',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.navy,
                              ),
                            ),
                            Text(
                              '${file.name} • ${_formatFileSize(bytes.length)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppTheme.fontSmall,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close preview',
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceSoft,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: _filePreview(file.name, bytes),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Submitting sends this file to your coordinator for review.',
                    style: TextStyle(
                      fontSize: AppTheme.fontSmall,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Keep editing'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        icon: const Icon(Icons.send_outlined, size: 17),
                        label: const Text('Submit document'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (shouldSubmit == true) await _submitStagedFile(file);
  }

  Widget _filePreview(String fileName, Uint8List bytes) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'pdf') {
      return PdfViewer.data(bytes, sourceName: fileName);
    }
    if ({'png', 'jpg', 'jpeg'}.contains(extension)) {
      return InteractiveViewer(
        minScale: .5,
        maxScale: 4,
        child: Center(
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                const Center(child: Text('This image preview is unavailable.')),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              size: 46,
              color: AppTheme.blue,
            ),
            const SizedBox(height: 10),
            Text(
              fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Word document preview is unavailable here. Confirm to submit this file.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitStagedFile(PlatformFile file) async {
    if (!_canUpload) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      if (widget.record == null) {
        await widget.repository.submitRequirement(
          user: widget.user,
          title: widget.definition.title,
          definition: widget.definition,
          file: file,
        );
      } else {
        await widget.repository.resubmitRequirement(
          user: widget.user,
          requirement: widget.record!,
          definitionId: widget.definition.id,
          file: file,
        );
      }
      if (!mounted) return;
      setState(() {
        _stagedFile = null;
        _stagedBytes = null;
        _successMessage =
            'Submitted successfully. Your coordinator can review this document now.';
      });
      widget.onSubmitted(widget.definition.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Document submitted. Your coordinator can review it now.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _errorMessage = '$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

base class _DroppedDocumentPlatformFile extends PlatformFile {
  _DroppedDocumentPlatformFile(this.name, this._bytes);

  @override
  final String name;
  final Uint8List _bytes;

  @override
  Uri get uri => Uri.parse('memory://document/${Uri.encodeComponent(name)}');

  @override
  String? get path => null;

  @override
  XFile get xFile => XFile.fromData(_bytes, name: name);

  @override
  int? lengthSync() => _bytes.length;

  @override
  Future<int?> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => _bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield _bytes;
  }
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _SavedRepositoryView {
  const _SavedRepositoryView({
    required this.query,
    required this.status,
    required this.category,
    required this.program,
    required this.tab,
    required this.folderPath,
  });

  final String query;
  final ReviewStatus? status;
  final String category;
  final String program;
  final int tab;
  final List<String> folderPath;
}

class DocumentRepositoryScreen extends StatefulWidget {
  const DocumentRepositoryScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final AppUser user;
  final PracticumRepository repository;

  @override
  State<DocumentRepositoryScreen> createState() =>
      _DocumentRepositoryScreenState();
}

class _DocumentRepositoryScreenState extends State<DocumentRepositoryScreen> {
  late Stream<List<AppUser>> _roster;
  late Stream<List<RequirementRecord>> _documents;
  List<String> _folderPath = [];
  bool _showFolders = false;

  void _subscribe() {
    _roster = widget.user.role == UserRole.student
        ? Stream.value([widget.user])
        : widget.repository.watchStudentsFor(widget.user);
    _documents = widget.repository.watchRepositoryDocuments(widget.user);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(DocumentRepositoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.role != widget.user.role) {
      _subscribe();
      _folderPath = [];
      _selected = null;
      _savedView = null;
    }
  }

  String _query = '';
  ReviewStatus? _status;
  String _category = 'All Categories';
  String _program = 'All Programs';
  int _tab = 0;
  RequirementRecord? _selected;
  _SavedRepositoryView? _savedView;
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _saveView() {
    setState(() {
      _savedView = _SavedRepositoryView(
        query: _query,
        status: _status,
        category: _category,
        program: _program,
        tab: _tab,
        folderPath: _folderPath,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Current repository view saved for this session.'),
      ),
    );
  }

  void _restoreView() {
    final saved = _savedView;
    if (saved == null) return;
    setState(() {
      _query = saved.query;
      _queryController.text = saved.query;
      _status = saved.status;
      _category = saved.category;
      _program = saved.program;
      _tab = saved.tab;
      _folderPath = saved.folderPath;
      _selected = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved repository view restored.')),
    );
  }

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Document Repository',
    subtitle: 'Find internship files by student, program, or review status.',
    eyebrow: 'Home  ›  Document Repository',
    actions: [
      OutlinedButton.icon(
        onPressed: _saveView,
        icon: const Icon(Icons.bookmark_add_outlined, size: 16),
        label: const Text('Save View'),
      ),
      if (_savedView != null)
        TextButton.icon(
          onPressed: _restoreView,
          icon: const Icon(Icons.restore_outlined, size: 16),
          label: const Text('Restore View'),
        ),
    ],
    child: StreamBuilder<List<AppUser>>(
      stream: _roster,
      builder: (context, roster) => StreamBuilder<List<RequirementRecord>>(
        stream: _documents,
        builder: (context, snapshot) {
          if (snapshot.hasError || roster.hasError) {
            return const Center(
              child: Text('Could not load the document directory.'),
            );
          }
          if (!snapshot.hasData ||
              !roster.hasData ||
              snapshot.connectionState == ConnectionState.waiting ||
              roster.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final directory = RepositoryFolder.build(
            roster.data!,
            snapshot.data!,
          );
          final chain = directory.resolve(_folderPath);
          final all = chain.last.documents.toList()
            ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
          final categories = {
            'All Categories',
            ...all.map((r) => r.category),
          }.toList();
          final programs = {
            'All Programs',
            ...all.map((r) => r.program).whereType<String>(),
          }.toList();
          final tabFiltered = all.where((record) {
            if (record.archived) return _tab == 4;
            return switch (_tab) {
              1 =>
                record.status == ReviewStatus.pending ||
                    record.status == ReviewStatus.underReview,
              2 => record.status == ReviewStatus.verified,
              3 => record.status == ReviewStatus.needsRevision,
              4 => record.archived,
              _ => !record.archived,
            };
          }).toList();
          final records = tabFiltered.where((record) {
            final haystack =
                '${record.title} ${record.fileName} ${record.studentName} ${record.studentNumber} ${record.institutionName}'
                    .toLowerCase();
            return (_query.isEmpty || haystack.contains(_query)) &&
                (_status == null || record.status == _status) &&
                (_category == 'All Categories' ||
                    record.category == _category) &&
                (_program == 'All Programs' || record.program == _program);
          }).toList();
          final selected =
              _selected != null &&
                  records.any((record) => record.id == _selected!.id)
              ? records.firstWhere((record) => record.id == _selected!.id)
              : records.firstOrNull;
          final counts = [
            all.where((r) => !r.archived).length,
            all
                .where(
                  (r) =>
                      !r.archived &&
                      (r.status == ReviewStatus.pending ||
                          r.status == ReviewStatus.underReview),
                )
                .length,
            all
                .where((r) => !r.archived && r.status == ReviewStatus.verified)
                .length,
            all
                .where(
                  (r) => !r.archived && r.status == ReviewStatus.needsRevision,
                )
                .length,
            all.where((r) => r.archived).length,
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WorkspaceTabs(
                labels: const [
                  'All Documents',
                  'For Verification',
                  'Verified',
                  'Needs Revision',
                  'Archived',
                ],
                counts: counts,
                selectedIndex: _tab,
                onSelected: (value) => setState(() => _tab = value),
              ),
              const SizedBox(height: 12),
              _RepositoryFilters(
                queryController: _queryController,
                queryChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                status: _status,
                category: _category,
                program: _program,
                categories: categories,
                programs: programs,
                onStatus: (value) => setState(() => _status = value),
                onCategory: (value) => setState(() => _category = value),
                onProgram: (value) => setState(() => _program = value),
                canReset:
                    _folderPath.isNotEmpty ||
                    _query.isNotEmpty ||
                    _status != null ||
                    _category != 'All Categories' ||
                    _program != 'All Programs',
                onReset: () => setState(() {
                  _folderPath = [];
                  _query = '';
                  _queryController.clear();
                  _status = null;
                  _category = 'All Categories';
                  _program = 'All Programs';
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final folders = RepositoryDirectory(
                      chain: chain,
                      onSelect: (path) => setState(() {
                        _folderPath = path;
                        _category = 'All Categories';
                        _program = 'All Programs';
                        _selected = null;
                      }),
                    );
                    final narrow = constraints.maxWidth < 850;
                    final list = Column(
                      children: [
                        if (constraints.maxWidth < 1180)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _showFolders = !_showFolders),
                              icon: Icon(
                                _showFolders
                                    ? Icons.list
                                    : Icons.folder_rounded,
                              ),
                              label: Text(
                                _showFolders
                                    ? 'Show documents'
                                    : 'Folders / ${chain.last.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        if (constraints.maxWidth < 1180 && _showFolders)
                          Expanded(child: folders)
                        else
                          Expanded(
                            child: _RepositoryList(
                              folderName: chain.last.label,
                              records: records,
                              selected: selected,
                              onSelect: (record) {
                                setState(() => _selected = record);
                                if (narrow) {
                                  showModalBottomSheet<void>(
                                    context: context,
                                    isScrollControlled: true,
                                    useSafeArea: true,
                                    showDragHandle: true,
                                    builder: (_) => FractionallySizedBox(
                                      heightFactor: 0.8,
                                      child: SingleChildScrollView(
                                        child: _RepositoryDetails(
                                          record: record,
                                          repository: widget.repository,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                      ],
                    );
                    final details = selected == null
                        ? const EmptyWorkflowState(
                            icon: Icons.folder_open_outlined,
                            title: 'No document selected',
                            message: 'Select a document to view its details.',
                          )
                        : _RepositoryDetails(
                            record: selected,
                            repository: widget.repository,
                          );
                    if (constraints.maxWidth >= 1180) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 246, child: folders),
                          const SizedBox(width: 12),
                          Expanded(child: list),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 315,
                            child: SingleChildScrollView(child: details),
                          ),
                        ],
                      );
                    }
                    if (constraints.maxWidth >= 850) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: list),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 315,
                            child: SingleChildScrollView(child: details),
                          ),
                        ],
                      );
                    }
                    return list;
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _RepositoryFilters extends StatelessWidget {
  const _RepositoryFilters({
    required this.queryController,
    required this.queryChanged,
    required this.status,
    required this.category,
    required this.program,
    required this.categories,
    required this.programs,
    required this.onStatus,
    required this.onCategory,
    required this.onProgram,
    required this.onReset,
    required this.canReset,
  });

  final TextEditingController queryController;
  final ValueChanged<String> queryChanged;
  final ReviewStatus? status;
  final String category;
  final String program;
  final List<String> categories;
  final List<String> programs;
  final ValueChanged<ReviewStatus?> onStatus;
  final ValueChanged<String> onCategory;
  final ValueChanged<String> onProgram;
  final VoidCallback onReset;
  final bool canReset;

  @override
  Widget build(BuildContext context) => WorkspaceFilterBar(
    search: TextField(
      controller: queryController,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, size: 19),
        hintText: 'Search files or students',
      ),
      onChanged: queryChanged,
    ),
    fields: [
      WorkspaceSelectField(
        key: ValueKey('repository-program-$program'),
        initialValue: program,
        label: 'Program',
        options: programs,
        onChanged: onProgram,
      ),
      WorkspaceSelectField(
        key: ValueKey('repository-category-$category'),
        initialValue: category,
        label: 'Category',
        options: categories,
        onChanged: onCategory,
      ),
      WorkspaceSelectField(
        key: ValueKey('repository-status-${status?.name}'),
        initialValue: status?.label ?? 'All Statuses',
        label: 'Status',
        options: [
          'All Statuses',
          ...ReviewStatus.values.map((value) => value.label),
        ],
        onChanged: (value) => onStatus(
          ReviewStatus.values
              .where((status) => status.label == value)
              .firstOrNull,
        ),
      ),
    ],
    onReset: onReset,
    canReset: canReset,
  );
}

class _RepositoryList extends StatelessWidget {
  const _RepositoryList({
    required this.records,
    required this.selected,
    required this.onSelect,
    required this.folderName,
  });

  final List<RequirementRecord> records;
  final RequirementRecord? selected;
  final ValueChanged<RequirementRecord> onSelect;
  final String folderName;

  @override
  Widget build(BuildContext context) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 610;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        folderName,
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  Text(
                    '${records.length} ${records.length == 1 ? 'file' : 'files'}',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (!compact && records.isNotEmpty) ...[
              const ColoredBox(
                color: AppTheme.surfaceSoft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text('File name', style: _headerStyle),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Student', style: _headerStyle),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text('Uploaded', style: _headerStyle),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text('Status', style: _headerStyle),
                      ),
                      SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: records.isEmpty
                  ? const EmptyWorkflowState(
                      icon: Icons.folder_off_outlined,
                      title: 'No matching documents',
                      message: 'Try a different folder or adjust the filters.',
                    )
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _recordRow(records[index], compact: compact),
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _recordRow(RequirementRecord record, {required bool compact}) {
    final active = selected?.id == record.id;
    final name = record.fileName ?? record.title;
    final pdf = name.toLowerCase().endsWith('.pdf');
    final status = StatusBadge(record.status.label, compact: true);
    final date = shortDate(record.submittedAt);
    final file = Row(
      spacing: 8,
      children: [
        Icon(
          pdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined,
          color: pdf ? AppTheme.danger : AppTheme.blue,
          size: 18,
        ),
        Expanded(
          child: Tooltip(
            message: name,
            excludeFromSemantics: true,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: () => onSelect(record),
        child: Ink(
          color: active ? AppTheme.surfaceBlue : AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: [
                    file,
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Text(
                            '${record.studentName} • $date',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                        ),
                        status,
                        const Icon(Icons.chevron_right_rounded, size: 16),
                      ],
                    ),
                  ],
                )
              : Row(
                  spacing: 12,
                  children: [
                    Expanded(flex: 5, child: file),
                    Expanded(
                      flex: 3,
                      child: Text(
                        record.studentName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 110, child: Text(date)),
                    SizedBox(
                      width: 110,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: status,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: AppTheme.muted,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    fontSize: AppTheme.fontCaption,
    color: AppTheme.muted,
    fontWeight: FontWeight.w700,
  );
}

class _RepositoryDetails extends StatelessWidget {
  const _RepositoryDetails({required this.record, required this.repository});
  final RequirementRecord record;
  final PracticumRepository repository;

  String get _fileType {
    final name = record.fileName ?? '';
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : 'File';
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Document details',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _fileType == 'PDF'
                    ? AppTheme.danger.withValues(alpha: .08)
                    : AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                _fileType == 'PDF'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.description_outlined,
                color: _fileType == 'PDF' ? AppTheme.danger : AppTheme.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName ?? record.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$_fileType • Version ${record.version}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () =>
              openStorageDocument(context, repository, record.storagePath),
          icon: const Icon(Icons.visibility_outlined, size: 15),
          label: const Text('Preview'),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openStorageDocument(
                  context,
                  repository,
                  record.storagePath,
                ),
                icon: const Icon(Icons.download_outlined, size: 15),
                label: const Text('Download'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openStorageDocument(
                  context,
                  repository,
                  record.storagePath,
                ),
                icon: const Icon(Icons.inventory_2_outlined, size: 15),
                label: const Text('Retrieve'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showVersionHistory(context),
          icon: const Icon(Icons.history, size: 15),
          label: const Text('View Version History'),
        ),
        const Divider(height: 22),
        const Text(
          'Document Information',
          style: TextStyle(
            fontSize: AppTheme.fontCaption,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        InfoRow('Student', record.studentName, labelWidth: 80),
        InfoRow('Student No.', record.studentNumber ?? '—', labelWidth: 80),
        InfoRow('Program', record.program ?? '—', labelWidth: 80),
        InfoRow('Category', record.category, labelWidth: 80),
        InfoRow('Institution', record.institutionName ?? '—', labelWidth: 80),
        InfoRow('Uploaded', shortDate(record.submittedAt), labelWidth: 80),
        InfoRow('Version', '${record.version}', labelWidth: 80),
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              const SizedBox(
                width: 80,
                child: Text(
                  'Status',
                  style: TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.muted,
                  ),
                ),
              ),
              StatusBadge(record.status.label, compact: true),
            ],
          ),
        ),
        if (record.remarks?.isNotEmpty == true) ...[
          const Divider(height: 22),
          const Text(
            'Coordinator Remarks',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            record.remarks!,
            style: const TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
              height: 1.35,
            ),
          ),
        ],
        const Divider(height: 22),
        const Text(
          'Version History',
          style: TextStyle(
            fontSize: AppTheme.fontCaption,
            fontWeight: FontWeight.w800,
          ),
        ),
        StreamBuilder<List<RequirementVersionRecord>>(
          stream: repository.watchRequirementVersions(record.id),
          builder: (context, snapshot) {
            final versions =
                snapshot.data ?? const <RequirementVersionRecord>[];
            return Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.circle,
                    size: 8,
                    color: AppTheme.blue,
                  ),
                  title: Text(
                    'v${record.version}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    '${shortDate(record.submittedAt)} • Current',
                    style: const TextStyle(fontSize: AppTheme.fontCaption),
                  ),
                ),
                ...versions
                    .take(4)
                    .map(
                      (version) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.circle_outlined,
                          size: 8,
                          color: AppTheme.muted,
                        ),
                        title: Text(
                          'v${version.version}',
                          style: const TextStyle(
                            fontSize: AppTheme.fontCaption,
                          ),
                        ),
                        subtitle: Text(
                          shortDate(version.submittedAt),
                          style: const TextStyle(
                            fontSize: AppTheme.fontCaption,
                          ),
                        ),
                        onTap: version.storagePath.isEmpty
                            ? null
                            : () => openStorageDocument(
                                context,
                                repository,
                                version.storagePath,
                              ),
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    ),
  );

  Future<void> _showVersionHistory(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Version History — ${record.title}'),
        content: SizedBox(
          width: 580,
          height: 420,
          child: StreamBuilder<List<RequirementVersionRecord>>(
            stream: repository.watchRequirementVersions(record.id),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Unable to load version history: ${snapshot.error}',
                  ),
                );
              }
              final versions =
                  snapshot.data ?? const <RequirementVersionRecord>[];
              return ListView(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.surfaceBlue,
                      foregroundColor: AppTheme.deepBlue,
                      child: Text('v${record.version}'),
                    ),
                    title: Text(record.fileName ?? record.title),
                    subtitle: Text(
                      '${DateFormat.yMMMd().add_jm().format(record.submittedAt)} • Current',
                    ),
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: () => openStorageDocument(
                      context,
                      repository,
                      record.storagePath,
                    ),
                  ),
                  const Divider(height: 1),
                  if (versions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No previous versions are available for this document.',
                        style: TextStyle(color: AppTheme.muted),
                      ),
                    )
                  else
                    ...versions.map(
                      (version) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.surfaceSoft,
                          foregroundColor: AppTheme.muted,
                          child: Text('v${version.version}'),
                        ),
                        title: Text(
                          version.fileName.isEmpty
                              ? record.title
                              : version.fileName,
                        ),
                        subtitle: Text(
                          version.submittedAt == null
                              ? 'Submission date unavailable'
                              : DateFormat.yMMMd().add_jm().format(
                                  version.submittedAt!,
                                ),
                        ),
                        trailing: version.storagePath.isEmpty
                            ? const Text('File unavailable')
                            : const Icon(Icons.open_in_new, size: 18),
                        onTap: version.storagePath.isEmpty
                            ? null
                            : () => openStorageDocument(
                                context,
                                repository,
                                version.storagePath,
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class DocumentReviewScreen extends StatefulWidget {
  const DocumentReviewScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final AppUser user;
  final PracticumRepository repository;

  @override
  State<DocumentReviewScreen> createState() => _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends State<DocumentReviewScreen> {
  static const _allPrograms = 'All programs';
  static const _allTypes = 'All document types';
  static const _allStatuses = 'All statuses';

  final _search = TextEditingController();
  late Stream<List<RequirementRecord>> _requirements;
  String _query = '';
  String _status = _allStatuses;
  String _program = _allPrograms;
  String _type = _allTypes;
  String? _selectedId;
  bool _openDetail = false;

  @override
  void initState() {
    super.initState();
    _requirements = widget.repository.watchRequirements(widget.user);
  }

  @override
  void didUpdateWidget(covariant DocumentReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.user.uid != widget.user.uid ||
        oldWidget.user.role != widget.user.role) {
      _requirements = widget.repository.watchRequirements(widget.user);
      _selectedId = null;
      _openDetail = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reset() => setState(() {
    _search.clear();
    _query = '';
    _status = _allStatuses;
    _program = _allPrograms;
    _type = _allTypes;
  });

  String? _programFor(RequirementRecord record) =>
      canonicalCasProgram(record.program) ?? record.program;

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Document Review',
    subtitle: 'Preview submissions and record your verification decisions.',
    child: StreamBuilder<List<RequirementRecord>>(
      stream: _requirements,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const EmptyWorkflowState(
            icon: Icons.error_outline,
            title: 'Could not load submissions',
            message: 'Try opening Document Review again.',
          );
        }
        if (!snapshot.hasData &&
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data ?? const <RequirementRecord>[];
        final programs = [
          _allPrograms,
          ...{
            ...all.map(_programFor).whereType<String>(),
          }.where((program) => program.trim().isNotEmpty),
        ];
        final types = [
          _allTypes,
          ...{...all.map((record) => record.category)},
        ];
        final records = all.where((record) {
          final haystack =
              '${record.studentName} ${record.studentNumber ?? ''} ${record.title} ${record.fileName ?? ''}'
                  .toLowerCase();
          return haystack.contains(_query) &&
              (_status == _allStatuses || record.status.label == _status) &&
              (_program == _allPrograms || _programFor(record) == _program) &&
              (_type == _allTypes || record.category == _type);
        }).toList();
        final selected =
            records.where((record) => record.id == _selectedId).firstOrNull ??
            records.firstOrNull;

        return LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 920;
            final list = _ReviewList(
              records: records,
              selected: split ? selected : null,
              onSelect: (record) => setState(() {
                _selectedId = record.id;
                _openDetail = true;
              }),
            );
            final detail = selected == null
                ? const Card(
                    child: EmptyWorkflowState(
                      icon: Icons.rate_review_outlined,
                      title: 'No submission selected',
                      message: 'Select a document to review it.',
                    ),
                  )
                : _ReviewDetail(
                    key: ValueKey(selected.id),
                    record: selected,
                    repository: widget.repository,
                    onStatus: (status, feedback) =>
                        _saveStatus(selected, status, feedback),
                  );

            if (!split && _openDetail && selected != null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _openDetail = false),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back to submissions'),
                  ),
                  Expanded(
                    child: SizedBox(width: double.infinity, child: detail),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                _toolbar(context, programs, types, split: split),
                Expanded(
                  child: split
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 12,
                          children: [
                            Expanded(flex: 5, child: list),
                            Expanded(flex: 6, child: detail),
                          ],
                        )
                      : list,
                ),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _toolbar(
    BuildContext context,
    List<String> programs,
    List<String> types, {
    required bool split,
  }) {
    final search = TextField(
      controller: _search,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search_rounded, size: 20),
        hintText: 'Search submissions',
        constraints: BoxConstraints(minHeight: 54),
      ),
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    );
    final filtered =
        _status != _allStatuses ||
        _program != _allPrograms ||
        _type != _allTypes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          spacing: 10,
          children: [
            Expanded(flex: 3, child: search),
            if (split) ...[
              for (final field in _filterFields(programs, types, setState))
                Expanded(flex: 2, child: field),
              TextButton.icon(
                onPressed: filtered || _query.isNotEmpty ? _reset : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset'),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => _showFilters(context, programs, types),
                icon: Icon(
                  filtered ? Icons.filter_alt_rounded : Icons.tune_rounded,
                  size: 18,
                ),
                label: const Text('Filters'),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _filterFields(
    List<String> programs,
    List<String> types,
    StateSetter update,
  ) => [
    WorkspaceSelectField(
      key: ValueKey('program-$_program'),
      label: 'Program',
      initialValue: programs.contains(_program) ? _program : _allPrograms,
      options: programs,
      onChanged: (value) => update(() => _program = value),
    ),
    WorkspaceSelectField(
      key: ValueKey('type-$_type'),
      label: 'Document type',
      initialValue: types.contains(_type) ? _type : _allTypes,
      options: types,
      onChanged: (value) => update(() => _type = value),
    ),
    WorkspaceSelectField(
      key: ValueKey('status-$_status'),
      label: 'Status',
      initialValue: _status,
      options: [
        _allStatuses,
        ...ReviewStatus.values.map((status) => status.label),
      ],
      onChanged: (value) => update(() => _status = value),
    ),
  ];

  void _showFilters(
    BuildContext context,
    List<String> programs,
    List<String> types,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Filter submissions'),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: _filterFields(programs, types, (change) {
                setState(change);
                refresh(() {});
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _reset();
                refresh(() {});
              },
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveStatus(
    RequirementRecord record,
    ReviewStatus status,
    String feedback,
  ) async {
    await widget.repository.updateRequirementStatus(
      requirementId: record.id,
      status: status,
      remarks: feedback,
      reviewer: widget.user,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Document marked ${status.label.toLowerCase()}.'),
        ),
      );
    }
  }
}

class _ReviewList extends StatelessWidget {
  const _ReviewList({
    required this.records,
    required this.selected,
    required this.onSelect,
  });

  final List<RequirementRecord> records;
  final RequirementRecord? selected;
  final ValueChanged<RequirementRecord> onSelect;

  @override
  Widget build(BuildContext context) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final table = constraints.maxWidth >= 480;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Submissions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Text(
                    '${records.length} ${records.length == 1 ? 'result' : 'results'}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (table && records.isNotEmpty) ...[
              const ColoredBox(
                color: AppTheme.surfaceSoft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('Student', style: _headerStyle),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('Document', style: _headerStyle),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('Submitted', style: _headerStyle),
                      ),
                      SizedBox(
                        width: _statusWidth,
                        child: Text('Status', style: _headerStyle),
                      ),
                      SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
            Expanded(
              child: records.isEmpty
                  ? const EmptyWorkflowState(
                      icon: Icons.inbox_outlined,
                      title: 'No submissions found',
                      message: 'Adjust the review filters.',
                    )
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _row(records[index], table: table),
                    ),
            ),
          ],
        );
      },
    ),
  );

  Widget _row(RequirementRecord record, {required bool table}) {
    final active = selected?.id == record.id;
    final status = StatusBadge(record.status.label, compact: true);
    final chevron = Icon(
      Icons.chevron_right_rounded,
      size: 16,
      color: active ? AppTheme.blue : AppTheme.muted,
    );
    final id = record.studentNumber ?? '';
    final date = shortDate(record.submittedAt);

    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: () => onSelect(record),
        child: Ink(
          color: active ? AppTheme.surfaceBlue : AppTheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: table
              ? Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          _cell(record.studentName, primary: true),
                          if (id.isNotEmpty) _cell(id),
                        ],
                      ),
                    ),
                    Expanded(flex: 3, child: _cell(record.title)),
                    Expanded(flex: 2, child: _cell(date)),
                    SizedBox(
                      width: _statusWidth,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: status,
                      ),
                    ),
                    chevron,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 5,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(child: _cell(record.title, primary: true)),
                        status,
                        chevron,
                      ],
                    ),
                    _cell(
                      [
                        record.studentName,
                        id,
                        date,
                      ].where((value) => value.isNotEmpty).join(' • '),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  static const double _statusWidth = 120;
  static const _headerStyle = TextStyle(
    fontSize: AppTheme.fontCaption,
    color: AppTheme.muted,
    fontWeight: FontWeight.w700,
  );

  Widget _cell(String value, {bool primary = false}) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: primary ? AppTheme.fontSmall : AppTheme.fontCaption,
      color: primary ? AppTheme.text : AppTheme.muted,
      fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
    ),
  );
}

class _ReviewDetail extends StatefulWidget {
  const _ReviewDetail({
    super.key,
    required this.record,
    required this.repository,
    required this.onStatus,
  });

  final RequirementRecord record;
  final PracticumRepository repository;
  final Future<void> Function(ReviewStatus status, String feedback) onStatus;

  @override
  State<_ReviewDetail> createState() => _ReviewDetailState();
}

class _ReviewDetailState extends State<_ReviewDetail> {
  int _tab = 0;
  bool _saving = false;
  late final TextEditingController _feedback;
  String? _previewPath;
  Future<String>? _previewUrlFuture;

  @override
  void initState() {
    super.initState();
    _feedback = TextEditingController(text: widget.record.remarks);
  }

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReviewDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.storagePath != widget.record.storagePath) {
      _tab = 0;
      _previewPath = null;
      _previewUrlFuture = null;
    }
    if (oldWidget.record.remarks != widget.record.remarks &&
        _feedback.text == (oldWidget.record.remarks ?? '')) {
      _feedback.text = widget.record.remarks ?? '';
    }
  }

  Future<void> _decide(ReviewStatus status) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onStatus(status, _feedback.text);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the review. $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 300;
        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              _tabBody(context),
              TextField(
                controller: _feedback,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'Coordinator feedback',
                ),
              ),
            ],
          ),
        );
        final panel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            widget.record.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          [
                                widget.record.studentName,
                                widget.record.studentNumber,
                              ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' • '),
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(widget.record.status.label, compact: true),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WorkspaceTabs(
                labels: const [
                  'Document',
                  'Student info',
                  'Submission details',
                  'History',
                  'Comments',
                ],
                selectedIndex: _tab,
                onSelected: (value) => setState(() => _tab = value),
              ),
            ),
            if (short)
              content
            else
              Expanded(child: SingleChildScrollView(child: content)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _decide(ReviewStatus.needsRevision),
                    child: const Text('Request revision'),
                  ),
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => _decide(ReviewStatus.rejected),
                    child: const Text('Reject'),
                  ),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _decide(ReviewStatus.verified),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
          ],
        );
        return short ? SingleChildScrollView(child: panel) : panel;
      },
    ),
  );

  Widget _tabBody(BuildContext context) => switch (_tab) {
    1 => _studentInfo(),
    2 => _submissionDetails(),
    3 => _history(),
    4 => _comments(),
    _ => _documentPreview(context),
  };

  Widget _documentPreview(BuildContext context) {
    final fileName = widget.record.fileName?.trim().isNotEmpty == true
        ? widget.record.fileName!.trim()
        : 'Submitted document';
    final storagePath = widget.record.storagePath?.trim() ?? '';
    final extension = fileName.split('.').last.toLowerCase();
    final canPreviewInline = {'pdf', 'png', 'jpg', 'jpeg'}.contains(extension);

    return Container(
      height: 320,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.description_outlined,
                  size: 17,
                  color: AppTheme.muted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSmall,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Open full document',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: storagePath.isEmpty
                      ? null
                      : () => openStorageDocument(
                          context,
                          widget.repository,
                          storagePath,
                        ),
                  icon: const Icon(Icons.open_in_new, size: 17),
                ),
              ],
            ),
          ),
          Expanded(
            child: storagePath.isEmpty
                ? _previewMessage(
                    title: 'No uploaded file',
                    message: 'This submission has no storage file attached.',
                  )
                : !canPreviewInline
                ? _previewMessage(
                    title: 'Inline preview unavailable',
                    message:
                        'This file type can be opened or downloaded, but this browser does not preview it here.',
                    action: OutlinedButton.icon(
                      onPressed: () => openStorageDocument(
                        context,
                        widget.repository,
                        storagePath,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Open document'),
                    ),
                  )
                : _loadInlinePreview(storagePath, isPdf: extension == 'pdf'),
          ),
        ],
      ),
    );
  }

  Future<String> _signedPreviewUrl(String storagePath) {
    if (_previewUrlFuture == null || _previewPath != storagePath) {
      _previewPath = storagePath;
      _previewUrlFuture = widget.repository.createDownloadUrl(storagePath);
    }
    return _previewUrlFuture!;
  }

  Widget _loadInlinePreview(String storagePath, {required bool isPdf}) =>
      FutureBuilder<String>(
        future: _signedPreviewUrl(storagePath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Preparing secure preview…'),
                ],
              ),
            );
          }
          final url = snapshot.data;
          if (snapshot.hasError || url == null || url.isEmpty) {
            return _previewFailure(
              storagePath,
              snapshot.error?.toString() ??
                  'Could not access the uploaded file.',
            );
          }
          if (isPdf) {
            return PdfViewer.uri(
              Uri.parse(url),
              key: ValueKey(url),
              params: PdfViewerParams(
                backgroundColor: AppTheme.background,
                margin: 12,
                pageDropShadow: BoxShadow(
                  color: AppTheme.navy.withValues(alpha: .15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
                errorBannerBuilder: (_, _, _, _) =>
                    _previewFailure(storagePath, 'Could not display this PDF.'),
              ),
            );
          }
          return Image.network(
            url,
            key: ValueKey(url),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) =>
                _previewFailure(storagePath, 'Could not display this image.'),
          );
        },
      );

  Widget _previewFailure(String storagePath, String message) => _previewMessage(
    title: 'Could not load preview',
    message: message,
    action: Wrap(
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => setState(() => _previewUrlFuture = null),
          child: const Text('Retry'),
        ),
        TextButton(
          onPressed: () =>
              openStorageDocument(context, widget.repository, storagePath),
          child: const Text('Open document'),
        ),
      ],
    ),
  );

  Widget _previewMessage({
    required String title,
    required String message,
    Widget? action,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: AppTheme.fontBody,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: AppTheme.fontSmall,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    ),
  );

  Widget _studentInfo() => _detailPanel(
    children: [
      const _DetailHeading('Student Information'),
      InfoRow('Name', widget.record.studentName, labelWidth: 110),
      InfoRow(
        'Student ID',
        widget.record.studentNumber ?? '—',
        labelWidth: 110,
      ),
      InfoRow('Program', widget.record.program ?? '—', labelWidth: 110),
      InfoRow(
        'Institution',
        widget.record.institutionName ?? '—',
        labelWidth: 110,
      ),
    ],
  );

  Widget _submissionDetails() => _detailPanel(
    children: [
      const _DetailHeading('Submission Details'),
      InfoRow('Document', widget.record.title, labelWidth: 110),
      InfoRow('File', widget.record.fileName ?? '—', labelWidth: 110),
      InfoRow('Category', widget.record.category, labelWidth: 110),
      InfoRow(
        'Submitted',
        shortDate(widget.record.submittedAt),
        labelWidth: 110,
      ),
      InfoRow('Due date', shortDate(widget.record.dueDate), labelWidth: 110),
      InfoRow('Version', 'v${widget.record.version}', labelWidth: 110),
      const SizedBox(height: 5),
      Align(
        alignment: Alignment.centerLeft,
        child: StatusBadge(widget.record.status.label, compact: true),
      ),
    ],
  );

  Widget _history() => Container(
    height: 245,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: StreamBuilder<List<RequirementVersionRecord>>(
      stream: widget.repository.watchRequirementVersions(widget.record.id),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Unable to load version history: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTheme.fontCaption,
                color: AppTheme.muted,
              ),
            ),
          );
        }
        final versions = snapshot.data ?? const <RequirementVersionRecord>[];
        return ListView(
          children: [
            const _DetailHeading('Submission History'),
            _historyTile(
              version: widget.record.version,
              fileName: widget.record.fileName ?? widget.record.title,
              date: widget.record.submittedAt,
              status: widget.record.status.label,
              current: true,
            ),
            ...versions.map(
              (item) => _historyTile(
                version: item.version,
                fileName: item.fileName,
                date: item.submittedAt,
                status: ReviewStatusLabel.parse(item.status).label,
                current: false,
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _historyTile({
    required int version,
    required String fileName,
    required DateTime? date,
    required String status,
    required bool current,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: current ? AppTheme.surfaceBlue : AppTheme.surfaceSoft,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        const Icon(Icons.history, size: 15, color: AppTheme.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version $version${current ? ' • Current' : ''}',
                style: const TextStyle(
                  fontSize: AppTheme.fontCaption,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTheme.fontCaption,
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              shortDate(date),
              style: const TextStyle(
                fontSize: AppTheme.fontCaption,
                color: AppTheme.muted,
              ),
            ),
            Text(
              status,
              style: const TextStyle(
                fontSize: AppTheme.fontCaption,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _comments() => _detailPanel(
    children: [
      const _DetailHeading('Review Comments'),
      Text(
        widget.record.remarks?.trim().isNotEmpty == true
            ? widget.record.remarks!
            : 'No coordinator feedback has been saved for this submission yet.',
        style: const TextStyle(
          fontSize: AppTheme.fontCaption,
          color: AppTheme.muted,
          height: 1.45,
        ),
      ),
      const SizedBox(height: 12),
      InfoRow('Reviewed by', widget.record.reviewedBy ?? '—', labelWidth: 110),
      InfoRow(
        'Reviewed on',
        shortDate(widget.record.reviewedAt),
        labelWidth: 110,
      ),
    ],
  );

  Widget _detailPanel({required List<Widget> children}) => Container(
    height: 245,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppTheme.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class _DetailHeading extends StatelessWidget {
  const _DetailHeading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: AppTheme.fontSmall,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class RequirementDefinitionAdminScreen extends StatelessWidget {
  const RequirementDefinitionAdminScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Requirement Submission Bins',
    subtitle: user.role == UserRole.admin
        ? 'Configure document instructions, forms, programs, and deadlines.'
        : 'View and remove requirement bins for your program.',
    actions: [
      if (user.role == UserRole.admin)
        FilledButton.icon(
          onPressed: () => _showEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('New requirement'),
        ),
    ],
    child: StreamBuilder<List<RequirementDefinition>>(
      stream: repository.watchRequirementDefinitions(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load requirement bins.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final program = user.casProgram;
        final definitions = snapshot.data!
            .where(
              (definition) =>
                  definition.active &&
                  (user.role == UserRole.admin ||
                      (program != null &&
                          canonicalCasProgram(definition.program) == program)),
            )
            .toList();
        if (definitions.isEmpty) {
          return EmptyWorkflowState(
            icon: Icons.inbox_outlined,
            title: 'No submission bins configured',
            message: user.role == UserRole.admin
                ? 'Create requirements so students can upload their documents.'
                : 'Requirement bins for your program will appear here.',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050
                ? 3
                : constraints.maxWidth >= 600
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final definition in definitions)
                      SizedBox(
                        width: width,
                        child: _RequirementBinCard(
                          definition: definition,
                          onEdit: user.role == UserRole.admin
                              ? () => _showEditor(context, existing: definition)
                              : null,
                          onRemove: () => _removeBin(context, definition),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        );
      },
    ),
  );

  Future<void> _removeBin(
    BuildContext context,
    RequirementDefinition definition,
  ) async {
    await showWorkspaceEditorDialog(
      context,
      title: 'Remove requirement bin?',
      saveLabel: 'Remove bin',
      width: 420,
      fields: (context, update) => Text(
        'Remove “${definition.title}” from the active requirements. Existing submissions stay in the repository.',
      ),
      onSave: () => repository.removeRequirementDefinition(user, definition.id),
    );
  }

  Future<void> _showEditor(
    BuildContext context, {
    RequirementDefinition? existing,
  }) async {
    final form = GlobalKey<FormState>();
    final title = TextEditingController(text: existing?.title);
    final description = TextEditingController(text: existing?.description);
    final instructions = TextEditingController(text: existing?.instructions);
    final category = TextEditingController(text: existing?.category);
    final savedProgram = existing?.program.trim() ?? '';
    var program = savedProgram.isEmpty || savedProgram == 'All Programs'
        ? 'All Programs'
        : canonicalCasProgram(savedProgram);
    final pdfTemplate = PdfTemplateEditorController(
      template: existing?.pdfTemplate,
    );
    var saving = false;
    String? saveError;
    var dueDate =
        existing?.dueDate ?? DateTime.now().add(const Duration(days: 30));
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          title: Text(
            existing == null ? 'New requirement bin' : 'Edit requirement bin',
          ),
          content: SizedBox(
            width: 640,
            child: Form(
              key: form,
              child: AbsorbPointer(
                absorbing: saving,
                child: SingleChildScrollView(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final categoryField = TextFormField(
                        controller: category,
                        decoration: const InputDecoration(
                          labelText: 'Category *',
                        ),
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) => value?.trim().isNotEmpty == true
                            ? null
                            : 'Enter a category.',
                      );
                      final dateField = OutlinedButton.icon(
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 18,
                        ),
                        label: Text('Due ${shortDate(dueDate)}'),
                        style: OutlinedButton.styleFrom(
                          alignment: AlignmentDirectional.centerStart,
                          minimumSize: const Size(0, 49),
                        ),
                        onPressed: () async {
                          final now = DateTime.now();
                          final firstDate = now.subtract(
                            const Duration(days: 365),
                          );
                          final lastDate = now.add(const Duration(days: 3650));
                          final selected = await showDatePicker(
                            context: context,
                            firstDate: dueDate.isBefore(firstDate)
                                ? dueDate
                                : firstDate,
                            lastDate: dueDate.isAfter(lastDate)
                                ? dueDate
                                : lastDate,
                            initialDate: dueDate,
                          );
                          if (selected != null && dialogContext.mounted) {
                            setDialogState(() => dueDate = selected);
                          }
                        },
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 12,
                        children: [
                          Text(
                            'Requirement details',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextFormField(
                            controller: title,
                            decoration: const InputDecoration(
                              labelText: 'Requirement title *',
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (value) =>
                                value?.trim().isNotEmpty == true
                                ? null
                                : 'Enter a requirement title.',
                          ),
                          if (constraints.maxWidth >= 480)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 12,
                              children: [
                                Expanded(child: categoryField),
                                Expanded(child: dateField),
                              ],
                            )
                          else ...[
                            categoryField,
                            dateField,
                          ],
                          WorkspaceSelectField(
                            label: 'Program *',
                            options: const ['All Programs', ...casPrograms],
                            initialValue: program,
                            onChanged: (value) => program = value,
                            validator: (value) => value == null
                                ? 'Select a program or All Programs.'
                                : null,
                            enabled: !saving,
                          ),
                          TextField(
                            controller: description,
                            minLines: 1,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Short description',
                            ),
                          ),
                          TextField(
                            controller: instructions,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'Submission instructions',
                            ),
                          ),
                          const Divider(height: 9),
                          PdfTemplateEditor(
                            controller: pdfTemplate,
                            repository: repository,
                          ),
                          if (saveError != null)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                saveError!,
                                style: const TextStyle(color: AppTheme.danger),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (form.currentState?.validate() != true) return;
                      setDialogState(() {
                        saving = true;
                        saveError = null;
                      });
                      try {
                        final template = await pdfTemplate.persist(
                          repository,
                          user,
                        );
                        await repository.saveRequirementDefinition(
                          actor: user,
                          id: existing?.id,
                          title: title.text,
                          description: description.text,
                          instructions: instructions.text,
                          category: category.text,
                          dueDate: dueDate,
                          program: program!,
                          officialFormUrl: existing?.officialFormUrl,
                          sampleFormUrl: existing?.sampleFormUrl,
                          pdfTemplate: template,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() => saveError = error.toString());
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save requirement'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    pdfTemplate.dispose();
    for (final controller in [title, description, instructions, category]) {
      controller.dispose();
    }
  }
}

class _RequirementBinCard extends StatelessWidget {
  const _RequirementBinCard({
    required this.definition,
    required this.onEdit,
    required this.onRemove,
  });

  final RequirementDefinition definition;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              const Icon(Icons.description_outlined, color: AppTheme.blue),
              Expanded(
                child: Text(
                  definition.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit ${definition.title}',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              IconButton(
                tooltip: 'Remove ${definition.title}',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          if (definition.description.trim().isNotEmpty)
            Text(
              definition.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.muted),
            ),
          const Divider(height: 1),
          InfoRow('Category', definition.category, labelWidth: 72),
          InfoRow('Program', definition.program, labelWidth: 72),
          InfoRow('Due date', shortDate(definition.dueDate), labelWidth: 72),
        ],
      ),
    ),
  );
}
