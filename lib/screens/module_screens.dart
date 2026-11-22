import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_feature.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../models/workflow_models.dart';
import '../services/practicum_repository.dart';
import 'account_settings_screen.dart';
import 'advanced_reports_screen.dart';
import 'archived_records_screen.dart';
import 'coordinator_dashboard_screen.dart';
import 'document_workflow_screens.dart';
import 'evaluation_management_screen.dart';
import 'dynamic_screens.dart';
import 'moa_management_screen.dart';
import 'notification_panel_screen.dart';
import 'student_profile_screen.dart';
import 'student_dashboard_screen.dart';
import 'workflow_shared.dart';

class ModuleRouter extends StatelessWidget {
  const ModuleRouter({
    super.key,
    required this.feature,
    required this.user,
    required this.repository,
    this.onNavigate,
  });

  final ValueChanged<AppFeature>? onNavigate;
  final AppFeature feature;
  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (!RoleAccess.canAccess(user.role, feature)) {
      return const _EmptyState(
        icon: Icons.lock_outline,
        title: 'Access denied',
        message: 'Your account is not authorized to open this module.',
      );
    }

    return switch (feature) {
      AppFeature.dashboard =>
        user.role == UserRole.student
            ? StudentDashboardScreen(
                user: user,
                repository: repository,
                onNavigate: onNavigate,
              )
            : CoordinatorDashboardScreen(user: user, repository: repository),
      AppFeature.statusTracker =>
        user.role == UserRole.student
            ? StudentStatusTrackerScreen(user: user, repository: repository)
            : DocumentReviewScreen(user: user, repository: repository),
      AppFeature.requirements =>
        user.role == UserRole.student
            ? StudentRequirementsChecklistScreen(
                user: user,
                repository: repository,
              )
            : RequirementDefinitionAdminScreen(
                user: user,
                repository: repository,
              ),
      AppFeature.documentReview => DocumentReviewScreen(
        user: user,
        repository: repository,
      ),
      AppFeature.repository =>
        user.role == UserRole.student
            ? DocumentSubmissionBinScreen(user: user, repository: repository)
            : DocumentRepositoryScreen(user: user, repository: repository),
      AppFeature.dtr => DtrScreen(user: user, repository: repository),
      AppFeature.notifications =>
        user.role == UserRole.admin
            ? NotificationsScreen(user: user, repository: repository)
            : StudentNotificationPanelScreen(
                user: user,
                repository: repository,
              ),
      AppFeature.reports => AdvancedReportsScreen(
        user: user,
        repository: repository,
      ),
      AppFeature.archivedRecords => ArchivedRecordsScreen(
        user: user,
        repository: repository,
      ),
      AppFeature.evaluations => EvaluationManagementScreen(
        user: user,
        repository: repository,
      ),
      AppFeature.tor => TorScreen(user: user, repository: repository),
      AppFeature.hours => HoursScreen(user: user, repository: repository),
      AppFeature.moa => MoaManagementScreen(user: user, repository: repository),
      AppFeature.students => StudentDirectoryScreen(
        actor: user,
        repository: repository,
      ),
      AppFeature.users => PeopleScreen(
        user: user,
        repository: repository,
        studentsOnly: false,
      ),
      AppFeature.audit => AuditLogScreen(repository: repository),
      AppFeature.settings => AccountSettingsScreen(
        user: user,
        repository: repository,
      ),
    };
  }
}

class RequirementsScreen extends StatelessWidget {
  const RequirementsScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ModuleHeader(
        title: user.role == UserRole.student
            ? 'My requirements'
            : 'Requirement review queue',
        subtitle: user.role == UserRole.student
            ? 'Upload PDF, Word, or image files and track verification.'
            : 'Review submissions, verify documents, or request a revision.',
        action: user.role == UserRole.student
            ? FilledButton.icon(
                onPressed: () => _showUploadDialog(context),
                icon: const Icon(Icons.upload_file),
                label: const Text('Submit document'),
              )
            : null,
      ),
      const SizedBox(height: 16),
      Expanded(
        child: StreamBuilder<List<RequirementRecord>>(
          stream: repository.watchRequirements(user),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error!);
            }
            final records = snapshot.data ?? const <RequirementRecord>[];
            if (records.isEmpty) {
              return const _EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No submissions yet',
                message: 'Submitted requirements will appear here.',
              );
            }
            return ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = records[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(Icons.description_outlined),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${item.studentName} • ${item.fileName ?? 'No file'}\n'
                      'Submitted ${DateFormat.yMMMd().add_jm().format(item.submittedAt)}'
                      '${item.remarks == null || item.remarks!.isEmpty ? '' : '\nRemarks: ${item.remarks}'}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatusChip(status: item.status),
                        IconButton(
                          tooltip: 'Copy secure file link',
                          onPressed: item.storagePath == null
                              ? null
                              : () async {
                                  try {
                                    final url = await repository
                                        .createDownloadUrl(item.storagePath!);
                                    await Clipboard.setData(
                                      ClipboardData(text: url),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Secure five-minute link copied.',
                                          ),
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('$error')),
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.link),
                        ),
                        if (user.role == UserRole.student &&
                            item.status == ReviewStatus.needsRevision)
                          IconButton(
                            tooltip: 'Replace corrected file',
                            onPressed: () => _resubmit(context, item),
                            icon: const Icon(Icons.upload_file_outlined),
                          ),
                        if (user.role != UserRole.student)
                          const SizedBox(width: 4),
                        if (user.role != UserRole.student)
                          IconButton(
                            tooltip: 'Review',
                            onPressed: () => _showReviewDialog(context, item),
                            icon: const Icon(Icons.rate_review_outlined),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );

  Future<void> _showUploadDialog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Submit a requirement')),
          body: DocumentSubmissionBinScreen(user: user, repository: repository),
        ),
      ),
    );
  }

  Future<void> _resubmit(
    BuildContext context,
    RequirementRecord requirement,
  ) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg'],
    );
    if (file == null || !context.mounted) return;
    try {
      await repository.resubmitRequirement(
        user: user,
        requirement: requirement,
        file: file,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Corrected file submitted for review.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showReviewDialog(
    BuildContext context,
    RequirementRecord item,
  ) async {
    final remarks = TextEditingController(text: item.remarks);
    ReviewStatus status = item.status;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Review ${item.title}'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ReviewStatus>(
                  isExpanded: true,
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ReviewStatus.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: remarks,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await repository.updateRequirementStatus(
                  requirementId: item.id,
                  status: status,
                  remarks: remarks.text.trim(),
                  reviewer: user,
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    remarks.dispose();
  }
}

class RepositoryScreen extends StatelessWidget {
  const RepositoryScreen({
    super.key,
    required this.user,
    required this.repository,
  });
  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _ModuleHeader(
        title: 'Document repository',
        subtitle: 'Your submitted files and their latest verification status.',
      ),
      const SizedBox(height: 16),
      Expanded(
        child: StreamBuilder<List<RequirementRecord>>(
          stream: repository.watchRequirements(user),
          builder: (context, snapshot) {
            final records = snapshot.data ?? const <RequirementRecord>[];
            if (records.isEmpty) {
              return const _EmptyState(
                icon: Icons.folder_off_outlined,
                title: 'Repository is empty',
                message:
                    'Upload a requirement to place a file in your repository.',
              );
            }
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 360,
                mainAxisExtent: 190,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final item = records[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.insert_drive_file_outlined,
                              color: AppTheme.blue,
                              size: 30,
                            ),
                            const Spacer(),
                            _StatusChip(status: item.status),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          item.fileName ?? 'No file name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: item.storagePath == null
                              ? null
                              : () async {
                                  final url = await repository
                                      .createDownloadUrl(item.storagePath!);
                                  if (!context.mounted) {
                                    return;
                                  }
                                  await Clipboard.setData(
                                    ClipboardData(text: url),
                                  );
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'A five-minute download link was copied.',
                                      ),
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.link),
                          label: const Text('Copy secure link'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}

class DtrScreen extends StatefulWidget {
  const DtrScreen({super.key, required this.user, required this.repository});
  final AppUser user;
  final PracticumRepository repository;

  @override
  State<DtrScreen> createState() => _DtrScreenState();
}

class _DtrScreenState extends State<DtrScreen> {
  Timer? _clockRefresh;
  AppUser get user => widget.user;
  PracticumRepository get repository => widget.repository;

  @override
  void initState() {
    super.initState();
    _clockRefresh = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockRefresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ModuleHeader(
        title: 'Daily Time Records',
        subtitle: user.role == UserRole.student
            ? 'Record your daily attendance, submit it for review, and monitor approved rendered hours.'
            : 'Review assigned interns\' Daily Time Records and monitor approved rendered hours.',
        action: null,
      ),
      const SizedBox(height: 16),
      Expanded(
        child: StreamBuilder<List<DtrRecord>>(
          stream: repository.watchDtr(user),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(error: snapshot.error!);
            }
            final records = snapshot.data ?? const <DtrRecord>[];
            if (records.isEmpty) {
              return ListView(
                children: [
                  if (user.role == UserRole.student) ...[
                    _clockAction(context, records),
                    const SizedBox(height: 16),
                  ],
                  _EmptyState(
                    icon: Icons.punch_clock_outlined,
                    title: 'No time records',
                    message: user.role == UserRole.student
                        ? 'Your submitted attendance records will appear here.'
                        : 'Submitted DTR entries from assigned interns will appear here.',
                  ),
                ],
              );
            }
            final approved = records
                .where((item) => item.status == ReviewStatus.verified)
                .toList();
            final total = approved.fold<double>(
              0,
              (sum, item) => sum + item.renderedHours,
            );
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final weekStart = today.subtract(Duration(days: today.weekday - 1));
            final monthStart = DateTime(now.year, now.month, 1);
            final weekly = approved
                .where((item) => !item.date.isBefore(weekStart))
                .fold<double>(0, (sum, item) => sum + item.renderedHours);
            final monthly = approved
                .where((item) => !item.date.isBefore(monthStart))
                .fold<double>(0, (sum, item) => sum + item.renderedHours);
            return ListView(
              children: [
                if (user.role == UserRole.student) ...[
                  _clockAction(context, records),
                  const SizedBox(height: 16),
                ],
                _ResponsiveStats(
                  cards: [
                    _StatData(
                      'Records',
                      '${records.length}',
                      Icons.list_alt_outlined,
                      AppTheme.blue,
                    ),
                    _StatData(
                      'Weekly Hours',
                      weekly.toStringAsFixed(1),
                      Icons.view_week_outlined,
                      AppTheme.blue,
                    ),
                    _StatData(
                      'Monthly Hours',
                      monthly.toStringAsFixed(1),
                      Icons.calendar_month_outlined,
                      AppTheme.purple,
                    ),
                    _StatData(
                      'Total Approved Hours',
                      total.toStringAsFixed(1),
                      Icons.timelapse_outlined,
                      AppTheme.success,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: WorkspaceTable(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Student')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Time in')),
                        DataColumn(label: Text('Time out')),
                        DataColumn(label: Text('Break')),
                        DataColumn(label: Text('Hours')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Remarks')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: records
                          .map(
                            (item) => DataRow(
                              cells: [
                                DataCell(Text(item.studentName)),
                                DataCell(
                                  Text(DateFormat.yMMMd().format(item.date)),
                                ),
                                DataCell(
                                  Text(DateFormat.jm().format(item.timeIn)),
                                ),
                                DataCell(
                                  Text(
                                    item.timeOut == null
                                        ? (item.isInProgress ? 'On shift' : '—')
                                        : DateFormat.jm().format(item.timeOut!),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    item.attendanceState == 'in_progress' ||
                                            item.scheduledEndAt != null
                                        ? 'Included in shift'
                                        : '${item.breakMinutes} min',
                                  ),
                                ),
                                DataCell(
                                  Text(item.renderedHours.toStringAsFixed(2)),
                                ),
                                DataCell(
                                  item.isInProgress
                                      ? const Chip(
                                          avatar: Icon(
                                            Icons.timelapse_outlined,
                                            size: 17,
                                          ),
                                          label: Text('On shift'),
                                        )
                                      : _StatusChip(status: item.status),
                                ),
                                DataCell(
                                  Text(
                                    !item.isInProgress &&
                                            item.renderedHours == 0
                                        ? 'Review attendance data before counting hours'
                                        : item.remarks ?? '—',
                                  ),
                                ),
                                DataCell(
                                  user.role == UserRole.student
                                      ? item.status ==
                                                    ReviewStatus
                                                        .needsRevision ||
                                                item.status ==
                                                    ReviewStatus.rejected
                                            ? IconButton(
                                                tooltip:
                                                    'Reply to coordinator review',
                                                onPressed: () =>
                                                    _showDtrResponseDialog(
                                                      context,
                                                      item,
                                                    ),
                                                icon: const Icon(
                                                  Icons.reply_outlined,
                                                ),
                                              )
                                            : const SizedBox.shrink()
                                      : item.isInProgress
                                      ? IconButton(
                                          tooltip:
                                              'Resolve this open shift with a reason',
                                          onPressed: () =>
                                              _showEarlyCloseDialog(
                                                context,
                                                item,
                                              ),
                                          icon: const Icon(
                                            Icons.logout_outlined,
                                          ),
                                        )
                                      : IconButton(
                                          tooltip: 'Review time record',
                                          onPressed: () =>
                                              _showReviewDialog(context, item),
                                          icon: const Icon(
                                            Icons.rate_review_outlined,
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _clockAction(BuildContext context, List<DtrRecord> records) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final todayRecord = records.where((record) {
      if (record.workDate != null) return record.workDate == todayKey;
      final date = record.date.toLocal();
      return DateTime(date.year, date.month, date.day) == today;
    }).firstOrNull;
    final active = records.where((record) => record.isInProgress).firstOrNull;
    if (active != null) {
      final end = active.scheduledEndAt;
      final missedDay = active.workDate != null && active.workDate != todayKey;
      final canSignOut =
          !missedDay &&
          end != null &&
          !DateTime.now().toUtc().isBefore(end.toUtc());
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppTheme.blue, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shift in progress',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      missedDay
                          ? 'This shift missed its scheduled Sign Out date. Ask your coordinator to resolve it.'
                          : end == null
                          ? 'Sign Out time unavailable'
                          : canSignOut
                          ? 'Scheduled shift has ended. You can Sign Out now.'
                          : 'Sign Out opens at ${DateFormat.jm().format(end.toLocal())}. Break time is included in the shift.',
                      style: const TextStyle(color: AppTheme.muted),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: canSignOut ? () => _clockOut(context) : null,
                icon: const Icon(Icons.logout_outlined),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      );
    }
    if (todayRecord != null) {
      return Card(
        child: ListTile(
          leading: const Icon(
            Icons.check_circle_outline,
            color: AppTheme.success,
          ),
          title: const Text('Today’s DTR record'),
          subtitle: Text(
            todayRecord.status == ReviewStatus.needsRevision ||
                    todayRecord.status == ReviewStatus.rejected
                ? 'Your coordinator returned it. Reply below; the recorded times stay unchanged.'
                : todayRecord.status == ReviewStatus.verified
                ? 'Your attendance was approved.'
                : 'Your attendance is waiting for coordinator review.',
          ),
        ),
      );
    }
    return StreamBuilder<InternshipProfileRecord?>(
      stream: repository.watchInternshipProfile(user.uid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final scheduleReady =
            profile?.shiftStartMinutes != null &&
            profile?.shiftEndMinutes != null &&
            profile!.shiftStartMinutes! < profile.shiftEndMinutes! &&
            profile.workDays.isNotEmpty;
        final message = snapshot.hasError
            ? 'Internship shift details are unavailable.'
            : scheduleReady
            ? 'Sign In uses server time and a check-in photo. Breaks are included in the shift.'
            : 'Ask your coordinator to enter your company shift in Internship Details.';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.camera_alt_outlined,
                  color: AppTheme.blue,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scheduleReady
                            ? 'Ready to start your shift?'
                            : 'Shift schedule needed',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        message,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: scheduleReady ? () => _clockIn(context) : null,
                  icon: const Icon(Icons.login_outlined),
                  label: const Text('Sign In'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _clockIn(BuildContext context) async {
    final photo = await showDialog<Uint8List>(
      context: context,
      builder: (_) => const _DtrCheckInCameraDialog(),
    );
    if (photo == null || !context.mounted) return;
    try {
      await repository.clockIn(student: user, photoBytes: photo);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed in. Your check-in photo and server time were recorded.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _clockOut(BuildContext context) async {
    try {
      await repository.clockOut(student: user);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed out. Your DTR was sent to your coordinator for review.',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _showEarlyCloseDialog(
    BuildContext context,
    DtrRecord item,
  ) async {
    final actualTime = TextEditingController();
    final reason = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Resolve ${item.studentName}’s open shift?'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: actualTime,
                decoration: const InputDecoration(
                  labelText: 'Actual sign-out (HH:mm, placement time)',
                  helperText:
                      'Required for a missed sign-out on a previous day.',
                ),
              ),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Reason for resolving the open shift',
                  helperText: 'Explain how the sign-out time was established.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await repository.closeShiftEarly(
                  coordinator: user,
                  record: item,
                  reason: reason.text,
                  actualTime: actualTime.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Shift closed and sent for DTR review.'),
                    ),
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('Resolve shift'),
          ),
        ],
      ),
    );
    actualTime.dispose();
    reason.dispose();
  }

  Future<void> _showDtrResponseDialog(
    BuildContext context,
    DtrRecord item,
  ) async {
    final response = TextEditingController(text: item.studentResponse ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reply to DTR review'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coordinator note: ${item.remarks ?? 'No review note provided.'}',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: response,
                minLines: 3,
                maxLines: 5,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Your response',
                  helperText: 'Attendance timestamps remain unchanged.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await repository.submitDtrResponse(
                  student: user,
                  record: item,
                  response: response.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Your response was sent to your coordinator.',
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('Send response'),
          ),
        ],
      ),
    );
    response.dispose();
  }

  Future<void> _showReviewDialog(BuildContext context, DtrRecord item) async {
    var status = item.status;
    final remarks = TextEditingController(text: item.remarks);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Review ${item.studentName} DTR'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.checkInPhotoPath != null) ...[
                  FutureBuilder<String?>(
                    future: repository.signedDtrPhotoUrl(
                      item.checkInPhotoPath!,
                    ),
                    builder: (context, snapshot) => snapshot.data == null
                        ? const ListTile(
                            leading: Icon(Icons.photo_outlined),
                            title: Text('Check-in photo unavailable'),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              snapshot.data!,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  'Time In: ${DateFormat.yMMMd().add_jm().format(item.timeIn)}',
                ),
                Text(
                  'Time Out: ${item.timeOut == null ? 'Open shift' : DateFormat.yMMMd().add_jm().format(item.timeOut!)}',
                ),
                if (item.exceptionReason != null)
                  Text('Coordinator exception: ${item.exceptionReason}'),
                if (item.studentResponse != null &&
                    item.studentResponse!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Student response: ${item.studentResponse}'),
                    ),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ReviewStatus>(
                  isExpanded: true,
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: ReviewStatus.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => status = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: remarks,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Remarks'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await repository.updateDtrStatus(
                  reviewer: user,
                  recordId: item.id,
                  status: status,
                  remarks: remarks.text,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save review'),
            ),
          ],
        ),
      ),
    );
    remarks.dispose();
  }
}

class _DtrCheckInCameraDialog extends StatefulWidget {
  const _DtrCheckInCameraDialog();

  @override
  State<_DtrCheckInCameraDialog> createState() =>
      _DtrCheckInCameraDialogState();
}

class _DtrCheckInCameraDialogState extends State<_DtrCheckInCameraDialog> {
  CameraController? _controller;
  Uint8List? _captured;
  String? _error;
  bool _loading = true;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }
      final camera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _captured = bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_captured == null ? 'Check-in photo' : 'Review photo'),
    content: SizedBox(
      width: 520,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: _captured != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_captured!, fit: BoxFit.cover),
              )
            : _loading
            ? const Center(child: CircularProgressIndicator())
            : _controller != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CameraPreview(_controller!),
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      _error ?? 'Camera unavailable.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Allow camera access in your browser or device settings before signing in.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_captured != null)
        OutlinedButton.icon(
          onPressed: () => setState(() => _captured = null),
          icon: const Icon(Icons.refresh),
          label: const Text('Retake'),
        ),
      if (_captured == null && _controller != null)
        FilledButton.icon(
          onPressed: _capturing ? null : _capture,
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(_capturing ? 'Capturing…' : 'Capture'),
        ),
      if (_captured != null)
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _captured),
          icon: const Icon(Icons.check),
          label: const Text('Use photo and Sign In'),
        ),
    ],
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final PracticumRepository repository;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) => StreamBuilder<List<NotificationRecord>>(
    stream: widget.repository.watchNotificationManagement(widget.user),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorState(error: snapshot.error!);
      }
      final all = snapshot.data ?? const <NotificationRecord>[];
      final records = all.where((item) {
        if (_query.isEmpty) return true;
        final haystack =
            '${item.title} ${item.message} ${item.targetRole} ${item.priority}'
                .toLowerCase();
        return haystack.contains(_query);
      }).toList();
      final active = all.where((item) => item.active && item.isDue).length;
      final scheduled = all
          .where(
            (item) => item.active && item.scheduledFor != null && !item.isDue,
          )
          .length;

      return WorkflowPage(
        title: 'Notification Management',
        subtitle:
            'Create, schedule, edit, deactivate, delete, and review delivery activity for internship notifications.',
        eyebrow: 'Administration  ›  Notifications',
        actions: [
          FilledButton.icon(
            onPressed: () => _showEditor(context),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Create Notification'),
          ),
        ],
        child: Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                StatCard(
                  label: 'Total Notifications',
                  value: '${all.length}',
                  icon: Icons.notifications_outlined,
                ),
                StatCard(
                  label: 'Active / Sent',
                  value: '$active',
                  icon: Icons.send_outlined,
                ),
                StatCard(
                  label: 'Scheduled',
                  value: '$scheduled',
                  icon: Icons.schedule_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search title, message, audience, or priority',
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: records.isEmpty
                  ? const _EmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: 'No notifications found',
                      message: 'Create a notification or adjust the search.',
                    )
                  : ListView.separated(
                      itemCount: records.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = records[index];
                        final state = !item.active
                            ? 'Inactive'
                            : item.scheduledFor != null && !item.isDue
                            ? 'Scheduled'
                            : 'Sent';
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceBlue,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_active_outlined,
                                    color: AppTheme.blue,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            item.title,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(state),
                                          ),
                                          Chip(
                                            visualDensity:
                                                VisualDensity.compact,
                                            label: Text(
                                              item.priority.toUpperCase(),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        item.message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Audience: ${item.targetRole}  •  '
                                        '${item.scheduledFor == null ? 'Created' : 'Scheduled'} '
                                        '${DateFormat.yMMMd().add_jm().format(item.scheduledFor ?? item.createdAt)}  •  '
                                        'Read by ${item.readBy.length}',
                                        style: const TextStyle(
                                          color: AppTheme.muted,
                                          fontSize: AppTheme.fontSmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: 'Notification actions',
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await _showEditor(
                                        context,
                                        existing: item,
                                      );
                                    } else if (value == 'toggle') {
                                      await widget.repository
                                          .setNotificationActive(
                                            actor: widget.user,
                                            notification: item,
                                            active: !item.active,
                                          );
                                    } else if (value == 'delete') {
                                      await _confirmDelete(context, item);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'toggle',
                                      child: Text(
                                        item.active ? 'Deactivate' : 'Activate',
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _showEditor(
    BuildContext context, {
    NotificationRecord? existing,
  }) async {
    final title = TextEditingController(text: existing?.title);
    final message = TextEditingController(text: existing?.message);
    final link = TextEditingController(text: existing?.linkUrl);
    var target = existing?.targetRole ?? 'student';
    if (target.startsWith('user:')) target = 'student';
    var priority = existing?.priority ?? 'normal';
    DateTime? scheduledFor = existing?.scheduledFor;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            existing == null ? 'Create notification' : 'Edit notification',
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: message,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Message'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: target,
                          decoration: const InputDecoration(
                            labelText: 'Audience',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'student',
                              child: Text('Student Interns'),
                            ),
                            DropdownMenuItem(
                              value: 'coordinator',
                              child: Text('Program Coordinators'),
                            ),
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('All signed-in users'),
                            ),
                          ],
                          onChanged: existing == null
                              ? (value) => setDialogState(
                                  () => target = value ?? 'student',
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: priority,
                          decoration: const InputDecoration(
                            labelText: 'Priority',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'normal',
                              child: Text('Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'high',
                              child: Text('High'),
                            ),
                            DropdownMenuItem(
                              value: 'urgent',
                              child: Text('Urgent'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(
                            () => priority = value ?? 'normal',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: link,
                    decoration: const InputDecoration(
                      labelText: 'Related link (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              firstDate: DateTime(now.year - 1),
                              lastDate: DateTime(now.year + 3),
                              initialDate: scheduledFor ?? now,
                            );
                            if (date == null || !context.mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: scheduledFor == null
                                  ? TimeOfDay.fromDateTime(now)
                                  : TimeOfDay.fromDateTime(scheduledFor!),
                            );
                            if (time == null) return;
                            setDialogState(() {
                              scheduledFor = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            scheduledFor == null
                                ? 'Send immediately'
                                : DateFormat.yMMMd().add_jm().format(
                                    scheduledFor!,
                                  ),
                          ),
                        ),
                      ),
                      if (scheduledFor != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Send immediately instead',
                          onPressed: () =>
                              setDialogState(() => scheduledFor = null),
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      ],
                    ],
                  ),
                ],
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
                      if (title.text.trim().isEmpty ||
                          message.text.trim().isEmpty) {
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        if (existing == null) {
                          await widget.repository.sendNotification(
                            actor: widget.user,
                            title: title.text,
                            message: message.text,
                            targetRole: target,
                            priority: priority,
                            scheduledFor: scheduledFor,
                            linkUrl: link.text,
                          );
                        } else {
                          await widget.repository.updateNotification(
                            actor: widget.user,
                            notification: existing,
                            title: title.text,
                            message: message.text,
                            priority: priority,
                            scheduledFor: scheduledFor,
                            linkUrl: link.text,
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        setDialogState(() => saving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    },
              child: Text(existing == null ? 'Publish' : 'Save changes'),
            ),
          ],
        ),
      ),
    );

    title.dispose();
    message.dispose();
    link.dispose();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    NotificationRecord item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete notification?'),
        content: Text(
          'Delete “${item.title}”? This removes the notification from the dashboard.',
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
    if (confirmed == true) {
      await widget.repository.deleteNotification(
        actor: widget.user,
        notification: item,
      );
    }
  }
}

class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      WorkspaceHeader(title: title, subtitle: subtitle, actions: [?action]);
}

class _ResponsiveStats extends StatelessWidget {
  const _ResponsiveStats({required this.cards});
  final List<_StatData> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth >= 1040
          ? (constraints.maxWidth - (cards.length - 1) * 16) / cards.length
          : constraints.maxWidth >= 600
          ? (constraints.maxWidth - 16) / 2
          : constraints.maxWidth;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: cards
            .map(
              (card) => SizedBox(
                width: width,
                child: _StatCard(data: card),
              ),
            )
            .toList(),
      );
    },
  );
}

class _StatData {
  const _StatData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: data.color.withValues(alpha: 0.12),
            foregroundColor: data.color,
            child: Icon(data.icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.value,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                Text(
                  data.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontSize: AppTheme.fontSmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final ReviewStatus status;

  @override
  Widget build(BuildContext context) => StatusBadge(status.label);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: AppTheme.subtle),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final raw = '$error';
    final permissionDenied =
        raw.contains('permission-denied') ||
        raw.toLowerCase().contains('insufficient permissions');
    return _EmptyState(
      icon: Icons.error_outline,
      title: 'Unable to load this module',
      message: permissionDenied
          ? 'Firestore denied access to this module. Deploy the updated '
                'firestore.rules, then sign out and sign back in so the latest '
                'coordinator permissions are used.'
          : raw,
    );
  }
}
