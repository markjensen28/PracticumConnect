import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../models/workflow_models.dart';
import '../services/practicum_repository.dart';
import 'advanced_reports_screen.dart';
import 'workflow_shared.dart';

const _studentCollegeOptions = [
  'College of Arts and Sciences',
  'College of Engineering',
  'College of Education',
  'College of Nursing and Health Sciences',
];

const _studentYearLevelOptions = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
  '5th Year',
];

class StudentDirectoryScreen extends StatefulWidget {
  const StudentDirectoryScreen({
    super.key,
    required this.actor,
    required this.repository,
  });

  final AppUser actor;
  final PracticumRepository repository;

  @override
  State<StudentDirectoryScreen> createState() => _StudentDirectoryScreenState();
}

class _StudentDirectoryScreenState extends State<StudentDirectoryScreen> {
  String _query = '';

  bool _importing = false;
  final Set<String> _pendingStudentActions = <String>{};

  Future<void> _managePendingStudent(AppUser student, String action) async {
    final studentNumber = student.studentNumber;
    if (studentNumber == null || studentNumber.trim().isEmpty) return;
    final resend = action == 'resend';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          resend ? 'Resend activation email?' : 'Remove pending student?',
        ),
        content: Text(
          resend
              ? 'Send a new activation link to ${student.email}? This retries the same saved address.'
              : 'Remove ${student.displayName} (${studentNumber}) and release the saved email and student number for a corrected roster entry? This deletes the unactivated account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(resend ? 'Resend invitation' : 'Remove student'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _pendingStudentActions.add(student.uid));
    try {
      await widget.repository.managePendingStudent(
        studentNumber,
        resendInvitation: resend,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resend
                ? 'Activation email resent to ${student.email}.'
                : 'Pending student removed. You can correct and reimport the roster row.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${resend ? 'resend the invitation' : 'remove the student'}: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingStudentActions.remove(student.uid));
    }
  }

  Future<void> _importRoster() async {
    setState(() => _importing = true);
    var processed = 0;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      if ((await file.length() ?? 0) > 262144) {
        throw const FormatException('Choose a roster smaller than 256 KB.');
      }
      final rows =
          jsonDecode(utf8.decode(await file.readAsBytes())) as List<dynamic>;
      final preview = await widget.repository.importStudentRoster(
        rows,
        preview: true,
      );
      if (!mounted) return;
      if (preview['legacy'] != 0) {
        throw StateError(
          'This list contains existing accounts. Review them with the roster migration command before importing.',
        );
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import official roster?'),
          content: Text(
            'Process ${rows.length} students from ${file.name} and email invitations to newly enrolled students.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import and invite'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      for (final row in rows) {
        await widget.repository.importStudentRoster([row], preview: false);
        processed++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processed $processed roster entries.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processed $processed entries. $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Student Internship Records',
    subtitle: 'Open a student profile to monitor placement and progress.',
    actions: [
      if (widget.actor.role == UserRole.admin)
        OutlinedButton.icon(
          onPressed: _importing ? null : _importRoster,
          icon: const Icon(Icons.person_add_alt),
          label: Text(
            _importing ? 'Processing roster' : 'Import official roster',
          ),
        ),
    ],
    child: StreamBuilder<List<AppUser>>(
      stream: widget.repository.watchStudentDirectory(widget.actor),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const EmptyWorkflowState(
            icon: Icons.groups_outlined,
            title: 'Internship records unavailable',
            message:
                'Student records are unavailable right now. Please try again later.',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final students = (snapshot.data ?? const <AppUser>[])
            .where(
              (student) =>
                  _query.isEmpty ||
                  '${student.displayName} ${student.studentNumber} ${student.program}'
                      .toLowerCase()
                      .contains(_query),
            )
            .toList();
        return Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search student, number, or program',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.toLowerCase()),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: students.isEmpty
                  ? EmptyWorkflowState(
                      icon: Icons.groups_outlined,
                      title: widget.actor.role == UserRole.coordinator
                          ? 'No assigned interns found'
                          : 'No student records found',
                      message: widget.actor.role == UserRole.coordinator
                          ? 'Ask the SIP Admin to confirm the student account is active and assigned to this coordinator.'
                          : 'Registered student accounts appear here.',
                    )
                  : ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              child: Text(_initials(student.displayName)),
                            ),
                            title: Text(
                              student.enrollmentStatus == 'pending'
                                  ? '${student.displayName} (Pending activation)'
                                  : student.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              '${student.studentNumber ?? 'No student number'} • '
                              '${student.program ?? 'Program not set'}\n'
                              'Coordinator: ${student.coordinatorName ?? 'Unassigned'}',
                            ),
                            isThreeLine: true,
                            trailing:
                                widget.actor.role == UserRole.admin &&
                                    student.enrollmentStatus == 'pending'
                                ? _pendingStudentActions.contains(student.uid)
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : PopupMenuButton<String>(
                                          tooltip: 'Pending student actions',
                                          onSelected: (action) =>
                                              _managePendingStudent(
                                                student,
                                                action,
                                              ),
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'resend',
                                              child: ListTile(
                                                dense: true,
                                                leading: Icon(
                                                  Icons
                                                      .mark_email_read_outlined,
                                                ),
                                                title: Text(
                                                  'Resend activation email',
                                                ),
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: ListTile(
                                                dense: true,
                                                leading: Icon(
                                                  Icons.person_remove_outlined,
                                                ),
                                                title: Text(
                                                  'Remove pending student',
                                                ),
                                              ),
                                            ),
                                          ],
                                        )
                                : const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text('Student Profile'),
                                  ),
                                  body: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: StudentInternshipProfileScreen(
                                      actor: widget.actor,
                                      student: student,
                                      repository: widget.repository,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );

  String _initials(String value) => value
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
      .join();
}

class StudentInternshipProfileScreen extends StatefulWidget {
  const StudentInternshipProfileScreen({
    super.key,
    required this.actor,
    required this.student,
    required this.repository,
  });

  final AppUser actor;
  final AppUser student;
  final PracticumRepository repository;

  @override
  State<StudentInternshipProfileScreen> createState() =>
      _StudentInternshipProfileScreenState();
}

class _StudentInternshipProfileScreenState
    extends State<StudentInternshipProfileScreen> {
  int _selectedTab = 0;

  AppUser get actor => widget.actor;
  AppUser get student => widget.student;
  PracticumRepository get repository => widget.repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<InternshipProfileRecord?>(
    stream: repository.watchInternshipProfile(student.uid),
    builder: (context, profileSnapshot) {
      final profile =
          profileSnapshot.data ??
          InternshipProfileRecord(studentId: student.uid);
      final profileAvailable =
          !profileSnapshot.hasError && profileSnapshot.data != null;
      final profileLoading =
          !profileSnapshot.hasData && !profileSnapshot.hasError;
      return StreamBuilder<List<RequirementRecord>>(
        stream: repository.watchRequirements(actor),
        builder: (context, requirementSnapshot) {
          final requirements =
              (requirementSnapshot.data ?? const <RequirementRecord>[])
                  .where((item) => item.studentId == student.uid)
                  .toList();
          final requirementsUnavailable = requirementSnapshot.hasError;
          final requirementsLoading =
              !requirementSnapshot.hasData && !requirementSnapshot.hasError;
          return StreamBuilder<List<DtrRecord>>(
            stream: repository.watchDtr(actor),
            builder: (context, dtrSnapshot) {
              final dtr = (dtrSnapshot.data ?? const <DtrRecord>[])
                  .where((item) => item.studentId == student.uid)
                  .toList();
              final dtrUnavailable = dtrSnapshot.hasError;
              final dtrLoading = !dtrSnapshot.hasData && !dtrSnapshot.hasError;
              final double? hours = dtrUnavailable || dtrLoading
                  ? null
                  : dtr
                        .where((item) => item.status == ReviewStatus.verified)
                        .fold<double>(
                          0,
                          (total, item) => total + item.renderedHours,
                        );
              return WorkflowPage(
                title: 'Student Internship Profile',
                subtitle: 'Consolidated internship and requirement record.',
                actions: [
                  if (actor.role == UserRole.admin)
                    FilledButton.icon(
                      onPressed: () => _showCoordinatorAssignment(context),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(
                        student.coordinatorId == null
                            ? 'Assign Program Coordinator'
                            : 'Change Program Coordinator',
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _editProfile(context, profile),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Update profile'),
                  ),
                ],
                child: ListView(
                  children: [
                    _ProfileHeader(
                      student: student,
                      profile: profile,
                      profileAvailable: profileAvailable,
                      profileLoading: profileLoading,
                      selectedTab: _selectedTab,
                      onTabSelected: (index) {
                        if (_selectedTab != index) {
                          setState(() => _selectedTab = index);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: KeyedSubtree(
                        key: ValueKey(_selectedTab),
                        child: switch (_selectedTab) {
                          0 => LayoutBuilder(
                            builder: (context, constraints) {
                              final wide = constraints.maxWidth >= 920;

                              final main = Column(
                                children: [
                                  _InternshipDetails(
                                    profile: profile,
                                    coordinatorName: student.coordinatorName,
                                    profileAvailable: profileAvailable,
                                    profileLoading: profileLoading,
                                    completedHours: hours,
                                    dtrLoading: dtrLoading,
                                  ),
                                  const SizedBox(height: 14),
                                  _ProgressCard(
                                    completedHours: hours,
                                    requiredHours: profile.requiredHours,
                                    available: profileAvailable,
                                    loading: profileLoading || dtrLoading,
                                  ),
                                  const SizedBox(height: 14),
                                  _RecentActivity(
                                    actor: actor,
                                    student: student,
                                    repository: repository,
                                  ),
                                ],
                              );

                              final side = Column(
                                children: [
                                  _RequiredDocuments(
                                    records: requirements,
                                    unavailable: requirementsUnavailable,
                                    loading: requirementsLoading,
                                  ),
                                  const SizedBox(height: 14),
                                  _QuickActions(
                                    profile: profile,
                                    actor: actor,
                                    student: student,
                                    repository: repository,
                                    onEdit: () =>
                                        _editProfile(context, profile),
                                    onViewDocuments: () =>
                                        setState(() => _selectedTab = 1),
                                    onViewEvaluation: () =>
                                        setState(() => _selectedTab = 2),
                                    onAssignCoordinator:
                                        actor.role == UserRole.admin
                                        ? () => _showCoordinatorAssignment(
                                            context,
                                          )
                                        : null,
                                    onRemoveCoordinator:
                                        actor.role == UserRole.admin &&
                                            student.coordinatorId != null
                                        ? () => _removeCoordinatorAssignment(
                                            context,
                                          )
                                        : null,
                                  ),
                                ],
                              );

                              if (!wide) {
                                return Column(
                                  children: [
                                    main,
                                    const SizedBox(height: 14),
                                    side,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 2, child: main),
                                  const SizedBox(width: 14),
                                  Expanded(child: side),
                                ],
                              );
                            },
                          ),

                          1 => _DocumentsTab(
                            records: requirements,
                            unavailable: requirementsUnavailable,
                            loading: requirementsLoading,
                          ),

                          2 => _EvaluationTab(
                            actor: actor,
                            student: student,
                            repository: repository,
                          ),

                          3 => _AttendanceTab(
                            records: dtr,
                            completedHours: hours,
                            requiredHours: profile.requiredHours,
                            available: profileAvailable && !dtrUnavailable,
                            loading: profileLoading || dtrLoading,
                          ),

                          4 => _RemarksTab(
                            remarks: profile.coordinatorRemarks,
                            available: profileAvailable,
                            loading: profileLoading,
                          ),

                          _ => const SizedBox.shrink(),
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );

  Future<void> _showCoordinatorAssignment(BuildContext context) async {
    if (actor.role != UserRole.admin) return;

    final coordinators =
        (await repository.watchUsers(role: UserRole.coordinator).first)
            .where(
              (coordinator) =>
                  coordinator.active && coordinator.isApprovedCoordinator,
            )
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));

    if (!context.mounted) return;
    if (coordinators.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No approved Program Coordinator accounts are available yet.',
          ),
        ),
      );
      return;
    }

    AppUser selected = coordinators.firstWhere(
      (item) => item.uid == student.coordinatorId,
      orElse: () => coordinators.first,
    );

    final assigned = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            student.coordinatorId == null
                ? 'Assign Program Coordinator'
                : 'Change Program Coordinator',
          ),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assign ${student.displayName} to an approved Program Coordinator.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<AppUser>(
                  isExpanded: true,
                  initialValue: selected,
                  decoration: const InputDecoration(
                    labelText: 'Program Coordinator',
                    prefixIcon: Icon(Icons.supervisor_account_outlined),
                  ),
                  items: coordinators
                      .map(
                        (coordinator) => DropdownMenuItem<AppUser>(
                          value: coordinator,
                          child: Text(
                            coordinator.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selected = value);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                try {
                  await repository.assignStudent(
                    actor: actor,
                    student: student,
                    coordinator: selected,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Assign'),
            ),
          ],
        ),
      ),
    );

    if (assigned == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${student.displayName} was assigned to ${selected.displayName}.',
          ),
        ),
      );
    }
  }

  Future<void> _removeCoordinatorAssignment(BuildContext context) async {
    if (actor.role != UserRole.admin || student.coordinatorId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Program Coordinator?'),
        content: Text(
          'Remove the current Program Coordinator assignment from ${student.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await repository.assignStudent(
        actor: actor,
        student: student,
        coordinator: null,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Program Coordinator assignment removed.'),
          ),
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

  Future<void> _editProfile(
    BuildContext context,
    InternshipProfileRecord profile,
  ) async {
    final existingProgram = student.program?.trim() ?? '';
    final programOptions = [
      ..._studentCollegeOptions,
      if (existingProgram.isNotEmpty &&
          !_studentCollegeOptions.contains(existingProgram))
        existingProgram,
    ];
    var selectedProgram = programOptions.contains(existingProgram)
        ? existingProgram
        : null;

    final existingYearLevel = student.yearLevel?.trim() ?? '';
    final normalizedYearLevel = _normalizeYearLevel(existingYearLevel);
    final yearLevelOptions = [
      ..._studentYearLevelOptions,
      if (existingYearLevel.isNotEmpty && normalizedYearLevel == null)
        existingYearLevel,
    ];
    var selectedYearLevel =
        normalizedYearLevel ??
        (existingYearLevel.isNotEmpty ? existingYearLevel : null);

    final storedAcademicYear = student.academicYear?.trim().isNotEmpty == true
        ? student.academicYear!.trim()
        : profile.academicYear?.trim() ?? '';
    final academicYear = TextEditingController(
      text: storedAcademicYear.isNotEmpty
          ? storedAcademicYear
          : _currentAcademicYear(DateTime.now()),
    );
    final academicDepartment = TextEditingController(text: student.department);
    final section = TextEditingController(text: student.section);
    final profileFormKey = GlobalKey<FormState>();
    final company = TextEditingController(text: profile.companyName);
    final department = TextEditingController(text: profile.department);
    final position = TextEditingController(text: profile.position);
    final requiredHours = TextEditingController(
      text: '${profile.requiredHours}',
    );
    final supervisor = TextEditingController(text: profile.supervisorName);
    final supervisorEmail = TextEditingController(
      text: profile.supervisorEmail,
    );
    final supervisorPhone = TextEditingController(
      text: profile.supervisorPhone,
    );
    final remarks = TextEditingController(text: profile.coordinatorRemarks);
    final timeZone = TextEditingController(text: profile.timeZone);
    final status = profile.status;
    var placementStatus = profile.placementStatus;
    var startDate = profile.startDate;
    var endDate = profile.endDate;
    var shiftStartMinutes = profile.shiftStartMinutes;
    var shiftEndMinutes = profile.shiftEndMinutes;
    final workDays = <int>{...profile.workDays};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Update ${student.displayName}'),
          content: SizedBox(
            width: 680,
            child: Form(
              key: profileFormKey,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dropdown(
                      'Program / College',
                      selectedProgram,
                      programOptions,
                      (value) => setDialogState(() => selectedProgram = value),
                      width: 350,
                      hint: 'Select a college',
                      required: true,
                    ),
                    _dropdown(
                      'Year level',
                      selectedYearLevel,
                      yearLevelOptions,
                      (value) =>
                          setDialogState(() => selectedYearLevel = value),
                      hint: 'Select year level',
                      required: true,
                    ),
                    _field(academicDepartment, 'Academic department'),
                    _field(section, 'Class section'),
                    _field(academicYear, 'Academic year'),
                    SizedBox(
                      width: 314,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'System internship stage',
                          helperText:
                              'Updated automatically from requirements, deployment, DTR hours, and evaluation.',
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    _dropdown(
                      'Placement status',
                      placementStatus,
                      const [
                        'Unassigned',
                        'Processing',
                        'Confirmed',
                        'Deployed',
                      ],
                      (value) => setDialogState(() => placementStatus = value),
                    ),
                    _field(company, 'Company / institution'),
                    _field(department, 'Department'),
                    _field(position, 'Position'),
                    _field(requiredHours, 'Required hours', number: true),
                    _dateButton(context, 'Start date', startDate, (value) {
                      setDialogState(() => startDate = value);
                    }),
                    _dateButton(context, 'End date', endDate, (value) {
                      setDialogState(() => endDate = value);
                    }),
                    _shiftTimeButton(
                      context,
                      'Shift starts',
                      shiftStartMinutes,
                      (value) =>
                          setDialogState(() => shiftStartMinutes = value),
                    ),
                    _shiftTimeButton(
                      context,
                      'Shift ends',
                      shiftEndMinutes,
                      (value) => setDialogState(() => shiftEndMinutes = value),
                    ),
                    SizedBox(
                      width: 640,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Scheduled work days',
                          helperText:
                              'Breaks are included in the shift for now.',
                        ),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final day in const [
                              (1, 'Mon'),
                              (2, 'Tue'),
                              (3, 'Wed'),
                              (4, 'Thu'),
                              (5, 'Fri'),
                              (6, 'Sat'),
                              (7, 'Sun'),
                            ])
                              FilterChip(
                                label: Text(day.$2),
                                selected: workDays.contains(day.$1),
                                onSelected: (selected) => setDialogState(() {
                                  if (selected) {
                                    workDays.add(day.$1);
                                  } else {
                                    workDays.remove(day.$1);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 314,
                      child: TextField(
                        controller: timeZone,
                        decoration: const InputDecoration(
                          labelText: 'Time zone',
                          helperText: 'IANA name, for example Asia/Manila',
                        ),
                      ),
                    ),
                    _field(supervisor, 'Supervisor name'),
                    _field(supervisorEmail, 'Supervisor email'),
                    _field(supervisorPhone, 'Supervisor phone'),
                    SizedBox(
                      width: 640,
                      child: TextField(
                        controller: remarks,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Coordinator remarks',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (profileFormKey.currentState?.validate() != true) return;
                final parsedHours = int.tryParse(requiredHours.text) ?? 400;
                await repository.saveInternshipProfile(
                  actor: actor,
                  student: student,
                  program: selectedProgram!,
                  academicDepartment: academicDepartment.text,
                  section: section.text,
                  yearLevel: selectedYearLevel!,
                  academicYear: academicYear.text,
                  profile: InternshipProfileRecord(
                    studentId: student.uid,
                    status: status,
                    placementStatus: placementStatus,
                    companyName: company.text,
                    department: department.text,
                    position: position.text,
                    startDate: startDate,
                    endDate: endDate,
                    shiftStartMinutes: shiftStartMinutes,
                    shiftEndMinutes: shiftEndMinutes,
                    workDays: (workDays.toList()..sort()),
                    timeZone: timeZone.text.trim().isEmpty
                        ? 'Asia/Manila'
                        : timeZone.text.trim(),
                    requiredHours: parsedHours,
                    supervisorName: supervisor.text,
                    supervisorEmail: supervisorEmail.text,
                    supervisorPhone: supervisorPhone.text,
                    coordinatorRemarks: remarks.text,
                  ),
                );
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save profile'),
            ),
          ],
        ),
      ),
    );
    for (final controller in [
      academicYear,
      academicDepartment,
      section,
      company,
      department,
      position,
      requiredHours,
      supervisor,
      supervisorEmail,
      supervisorPhone,
      remarks,
      timeZone,
    ]) {
      controller.dispose();
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => SizedBox(
    width: 310,
    child: TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _dropdown(
    String label,
    String? value,
    List<String> values,
    ValueChanged<String> onChanged, {
    double width = 310,
    String? hint,
    bool required = false,
  }) => SizedBox(
    width: width,
    child: FormField<String>(
      initialValue: values.contains(value) ? value : null,
      validator: required
          ? (item) => item == null || item.isEmpty ? 'Select $label' : null
          : null,
      builder: (field) => DropdownMenu<String>(
        width: width,
        menuHeight: 260,
        initialSelection: field.value,
        label: Text(label),
        hintText: hint,
        errorText: field.errorText,
        enableSearch: false,
        selectOnly: true,
        trailingIcon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        selectedTrailingIcon: const Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 20,
        ),
        alignmentOffset: const Offset(0, 8),
        menuStyle: MenuStyle(
          alignment: AlignmentDirectional.bottomStart,
          backgroundColor: const WidgetStatePropertyAll(AppTheme.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(5),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          fixedSize: WidgetStatePropertyAll(Size.fromWidth(width)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
        dropdownMenuEntries: values
            .map(
              (item) => DropdownMenuEntry<String>(
                value: item,
                label: item,
                trailingIcon: item == field.value
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTheme.blue,
                        size: 18,
                      )
                    : null,
              ),
            )
            .toList(),
        onSelected: (item) {
          if (item != null) {
            field.didChange(item);
            onChanged(item);
          }
        },
      ),
    ),
  );

  Widget _dateButton(
    BuildContext context,
    String label,
    DateTime? value,
    ValueChanged<DateTime> onChanged,
  ) => SizedBox(
    width: 310,
    child: OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month_outlined),
      label: Text('$label: ${shortDate(value)}'),
      onPressed: () async {
        final selected = await showDatePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2040),
          initialDate: value ?? DateTime.now(),
        );
        if (selected != null) {
          onChanged(selected);
        }
      },
    ),
  );

  Widget _shiftTimeButton(
    BuildContext context,
    String label,
    int? minutes,
    ValueChanged<int> onChanged,
  ) => SizedBox(
    width: 310,
    child: OutlinedButton.icon(
      icon: const Icon(Icons.schedule_outlined),
      label: Text(
        minutes == null
            ? '$label: Set time'
            : '$label: ${TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context)}',
      ),
      onPressed: () async {
        final initial = minutes == null
            ? const TimeOfDay(hour: 8, minute: 0)
            : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
        final selected = await showTimePicker(
          context: context,
          initialTime: initial,
        );
        if (selected != null) {
          onChanged(selected.hour * 60 + selected.minute);
        }
      },
    ),
  );
}

String _currentAcademicYear(DateTime date) {
  final startYear = date.month >= 6 ? date.year : date.year - 1;
  return '$startYear-${startYear + 1}';
}

String? _normalizeYearLevel(String value) {
  final normalized = value.trim().toLowerCase();
  const aliases = {
    '1': '1st Year',
    '1st': '1st Year',
    '1st year': '1st Year',
    'first year': '1st Year',
    '2': '2nd Year',
    '2nd': '2nd Year',
    '2nd year': '2nd Year',
    'second year': '2nd Year',
    '3': '3rd Year',
    '3rd': '3rd Year',
    '3rd year': '3rd Year',
    'third year': '3rd Year',
    '4': '4th Year',
    '4th': '4th Year',
    '4th year': '4th Year',
    'fourth year': '4th Year',
    '5': '5th Year',
    '5th': '5th Year',
    '5th year': '5th Year',
    'fifth year': '5th Year',
  };
  return aliases[normalized];
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.student,
    required this.profile,
    required this.profileAvailable,
    required this.profileLoading,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final AppUser student;
  final InternshipProfileRecord profile;
  final bool profileAvailable;
  final bool profileLoading;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppTheme.border,
                foregroundColor: AppTheme.muted,
                child: Text(
                  student.displayName.isEmpty
                      ? '?'
                      : student.displayName[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppTheme.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Student ID\n${_displayValue(student.studentNumber)}\nAcademic Year\n${_displayValue(student.academicYear?.trim().isNotEmpty == true ? student.academicYear : profile.academicYear)}',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: AppTheme.fontCaption,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: _HeaderValue('Program', _displayValue(student.program)),
              ),
              Expanded(
                flex: 2,
                child: _HeaderValue(
                  'Year Level',
                  _displayValue(student.yearLevel),
                ),
              ),
              Expanded(
                flex: 2,
                child: _HeaderValue(
                  'Email',
                  _displayValue(student.email, fallback: 'Unavailable'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Internship Status',
                      style: TextStyle(
                        fontSize: AppTheme.fontCaption,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    StatusBadge(
                      profileLoading
                          ? 'Loading…'
                          : profileAvailable
                          ? _displayValue(profile.status)
                          : 'Unavailable',
                      compact: true,
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Placement',
                      style: TextStyle(
                        fontSize: AppTheme.fontCaption,
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profileLoading
                          ? 'Loading…'
                          : !profileAvailable
                          ? 'Unavailable'
                          : _displayValue(
                              profile.companyName.isEmpty
                                  ? profile.placementStatus
                                  : profile.companyName,
                            ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTheme.fontCaption,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _ProfileTabs(
              selectedIndex: selectedTab,
              onSelected: onTabSelected,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileTabs extends StatelessWidget {
  const _ProfileTabs({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _labels = [
    'Overview',
    'Documents',
    'Evaluation',
    'Attendance',
    'Remarks',
  ];

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        _labels.length,
        (index) => _ProfileTab(
          _labels[index],
          active: selectedIndex == index,
          onTap: () => onSelected(index),
        ),
      ),
    ),
  );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab(this.label, {required this.onTap, this.active = false});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: active ? AppTheme.blue : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppTheme.blue : AppTheme.muted,
            fontSize: AppTheme.fontCaption,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab({
    required this.records,
    required this.unavailable,
    required this.loading,
  });

  final List<RequirementRecord> records;
  final bool unavailable;
  final bool loading;

  @override
  Widget build(BuildContext context) => _RequiredDocuments(
    records: records,
    unavailable: unavailable,
    loading: loading,
  );
}

class _EvaluationTab extends StatelessWidget {
  const _EvaluationTab({
    required this.actor,
    required this.student,
    required this.repository,
  });

  final AppUser actor;
  final AppUser student;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) {
    if (!actor.role.isStaff) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Unavailable. Supervisor evaluation details are restricted to authorized staff.',
          ),
        ),
      );
    }

    return StreamBuilder<List<SupervisorEvaluationRecord>>(
      stream: repository.watchEvaluationsFor(actor),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Unavailable'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Loading…'),
            ),
          );
        }

        final evaluations =
            (snapshot.data ?? const <SupervisorEvaluationRecord>[])
                .where((item) => item.studentId == student.uid)
                .toList();

        if (evaluations.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: EmptyWorkflowState(
                icon: Icons.assignment_turned_in_outlined,
                title: 'No supervisor evaluation yet',
                message:
                    'Supervisor evaluation records for this intern will appear here.',
              ),
            ),
          );
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Supervisor Evaluation',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: AppTheme.fontBody,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${evaluations.length} evaluation record'
                  '${evaluations.length == 1 ? '' : 's'} found.',
                  style: const TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Open Supervisor Evaluations for the complete confidential evaluation details.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: AppTheme.fontSmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({
    required this.records,
    required this.completedHours,
    required this.requiredHours,
    required this.available,
    required this.loading,
  });

  final List<DtrRecord> records;
  final double? completedHours;
  final int requiredHours;
  final bool available;
  final bool loading;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _ProgressCard(
        completedHours: completedHours,
        requiredHours: requiredHours,
        available: available,
        loading: loading,
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: !available
              ? const Text('Unavailable')
              : loading
              ? const Text('Loading…')
              : records.isEmpty
              ? const EmptyWorkflowState(
                  icon: Icons.punch_clock_outlined,
                  title: 'No attendance records',
                  message:
                      'Daily Time Record entries for this intern will appear here.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Attendance / DTR Records',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: AppTheme.fontBody,
                      ),
                    ),
                    const SizedBox(height: 12),
                    WorkspaceTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Time In')),
                          DataColumn(label: Text('Time Out')),
                          DataColumn(label: Text('Hours')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Remarks')),
                        ],
                        rows: records
                            .map(
                              (item) => DataRow(
                                cells: [
                                  DataCell(
                                    Text(DateFormat.yMMMd().format(item.date)),
                                  ),
                                  DataCell(
                                    Text(DateFormat.jm().format(item.timeIn)),
                                  ),
                                  DataCell(
                                    Text(
                                      item.timeOut == null
                                          ? (item.isInProgress
                                                ? 'On shift'
                                                : '—')
                                          : DateFormat.jm().format(
                                              item.timeOut!,
                                            ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(item.renderedHours.toStringAsFixed(2)),
                                  ),
                                  DataCell(Text(item.status.label)),
                                  DataCell(Text(item.remarks ?? '—')),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );
}

class _RemarksTab extends StatelessWidget {
  const _RemarksTab({
    required this.remarks,
    required this.available,
    required this.loading,
  });

  final String remarks;
  final bool available;
  final bool loading;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Coordinator Remarks',
                  style: TextStyle(
                    fontSize: AppTheme.fontBody,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  loading
                      ? 'Loading…'
                      : !available
                      ? 'Unavailable'
                      : remarks.trim().isEmpty
                      ? 'No coordinator remarks have been added yet.'
                      : remarks,
                  style: const TextStyle(color: AppTheme.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeaderValue extends StatelessWidget {
  const _HeaderValue(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: AppTheme.fontCaption,
          color: AppTheme.muted,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AppTheme.fontCaption,
          color: AppTheme.text,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _InternshipDetails extends StatelessWidget {
  const _InternshipDetails({
    required this.profile,
    required this.profileAvailable,
    required this.profileLoading,
    required this.completedHours,
    required this.dtrLoading,
    this.coordinatorName,
  });
  final InternshipProfileRecord profile;
  final bool profileAvailable;
  final bool profileLoading;
  final double? completedHours;
  final bool dtrLoading;
  final String? coordinatorName;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Internship Details',
    child: Column(
      children: [
        InfoRow('Company', _profileValue(profile.companyName), labelWidth: 105),
        InfoRow(
          'Department',
          _profileValue(profile.department),
          labelWidth: 105,
        ),
        InfoRow('Position', _profileValue(profile.position), labelWidth: 105),
        InfoRow(
          'Work shift',
          profile.shiftStartMinutes == null || profile.shiftEndMinutes == null
              ? 'Unavailable'
              : '${TimeOfDay(hour: profile.shiftStartMinutes! ~/ 60, minute: profile.shiftStartMinutes! % 60).format(context)} – ${TimeOfDay(hour: profile.shiftEndMinutes! ~/ 60, minute: profile.shiftEndMinutes! % 60).format(context)}',
          labelWidth: 105,
        ),
        InfoRow(
          'Work days',
          profile.workDays.isEmpty
              ? 'Unavailable'
              : profile.workDays
                    .map(
                      (day) =>
                          const {
                            1: 'Mon',
                            2: 'Tue',
                            3: 'Wed',
                            4: 'Thu',
                            5: 'Fri',
                            6: 'Sat',
                            7: 'Sun',
                          }[day] ??
                          '',
                    )
                    .where((day) => day.isNotEmpty)
                    .join(', '),
          labelWidth: 105,
        ),
        InfoRow('Time zone', profile.timeZone, labelWidth: 105),
        InfoRow('Start Date', _profileDate(profile.startDate), labelWidth: 105),
        InfoRow('End Date', _profileDate(profile.endDate), labelWidth: 105),
        InfoRow(
          'Required Hours',
          profileLoading
              ? 'Loading…'
              : profileAvailable
              ? '${profile.requiredHours}'
              : 'Unavailable',
          labelWidth: 105,
        ),
        InfoRow(
          'Completed Hours',
          dtrLoading
              ? 'Loading…'
              : completedHours == null
              ? 'Unavailable'
              : '${completedHours!.toStringAsFixed(1)} hours',
          labelWidth: 105,
        ),
        InfoRow(
          'Program Coordinator',
          _displayValue(coordinatorName),
          labelWidth: 105,
        ),
        InfoRow(
          'Company Supervisor',
          _profileValue(profile.supervisorName),
          labelWidth: 105,
        ),
      ],
    ),
  );

  String _profileValue(String value) => profileLoading
      ? 'Loading…'
      : profileAvailable
      ? _displayValue(value)
      : 'Unavailable';

  String _profileDate(DateTime? value) => profileLoading
      ? 'Loading…'
      : profileAvailable && value != null
      ? shortDate(value)
      : 'Unavailable';
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.completedHours,
    required this.requiredHours,
    required this.available,
    required this.loading,
  });
  final double? completedHours;
  final int requiredHours;
  final bool available;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final hasProgress =
        available && completedHours != null && requiredHours > 0;
    final progress = hasProgress
        ? (completedHours! / requiredHours).clamp(0, 1).toDouble()
        : 0.0;
    return SectionCard(
      title: 'Progress',
      trailing: Text(
        hasProgress
            ? '${(progress * 100).round()}%'
            : loading
            ? 'Loading…'
            : 'Unavailable',
        style: const TextStyle(
          fontSize: AppTheme.fontCaption,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: hasProgress
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: AppTheme.border,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Completed Hours: ${completedHours!.toStringAsFixed(1)} / $requiredHours',
                  style: const TextStyle(
                    fontSize: AppTheme.fontCaption,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            )
          : Text(
              loading ? 'Loading…' : 'Unavailable',
              style: const TextStyle(
                fontSize: AppTheme.fontCaption,
                color: AppTheme.muted,
              ),
            ),
    );
  }
}

class _RequiredDocuments extends StatelessWidget {
  const _RequiredDocuments({
    required this.records,
    required this.unavailable,
    required this.loading,
  });
  final List<RequirementRecord> records;
  final bool unavailable;
  final bool loading;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Required Documents',
    child: unavailable
        ? const Text(
            'Unavailable',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          )
        : loading
        ? const Text(
            'Loading…',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          )
        : records.isEmpty
        ? const Text(
            'No submissions yet.',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          )
        : Column(
            children: records.take(8).map((record) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 15,
                      color: AppTheme.muted,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppTheme.fontCaption),
                      ),
                    ),
                    StatusBadge(record.status.label, compact: true),
                  ],
                ),
              );
            }).toList(),
          ),
  );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.actor,
    required this.student,
    required this.repository,
  });
  final AppUser actor;
  final AppUser student;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Recent Activity',
    child: StreamBuilder<List<ActivityLogRecord>>(
      stream: repository.watchActivityLogs(actor: actor),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Unavailable',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Text(
            'Loading…',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          );
        }
        final records = (snapshot.data ?? const <ActivityLogRecord>[])
            .where(
              (record) =>
                  record.userId == student.uid ||
                  record.action.contains(student.displayName),
            )
            .take(6)
            .toList();
        if (records.isEmpty) {
          return const Text(
            'No recent activity.',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          );
        }
        return Column(
          children: records.map((record) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 15, color: AppTheme.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      record.action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: AppTheme.fontCaption),
                    ),
                  ),
                  Text(
                    DateFormat.MMMd().format(record.createdAt),
                    style: const TextStyle(
                      fontSize: AppTheme.fontCaption,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.profile,

    required this.actor,
    required this.student,
    required this.repository,
    required this.onEdit,
    required this.onViewDocuments,
    required this.onViewEvaluation,
    this.onAssignCoordinator,
    this.onRemoveCoordinator,
  });

  final InternshipProfileRecord profile;

  final AppUser actor;
  final AppUser student;
  final PracticumRepository repository;
  final VoidCallback onEdit;
  final VoidCallback onViewDocuments;
  final VoidCallback onViewEvaluation;
  final VoidCallback? onAssignCoordinator;
  final VoidCallback? onRemoveCoordinator;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Quick Actions',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onAssignCoordinator != null) ...[
          FilledButton.icon(
            onPressed: onAssignCoordinator,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
            label: Text(
              student.coordinatorId == null
                  ? 'Assign Program Coordinator'
                  : 'Change Program Coordinator',
            ),
          ),
          const SizedBox(height: 7),
        ],
        if (onRemoveCoordinator != null) ...[
          OutlinedButton.icon(
            onPressed: onRemoveCoordinator,
            icon: const Icon(Icons.person_remove_outlined, size: 15),
            label: const Text('Remove Coordinator Assignment'),
          ),
          const SizedBox(height: 7),
        ],
        FilledButton.icon(
          onPressed: onViewDocuments,
          icon: const Icon(Icons.description_outlined, size: 15),
          label: const Text('View All Documents'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: onViewEvaluation,
          icon: const Icon(Icons.assignment_turned_in_outlined, size: 15),
          label: const Text('View Evaluation'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 15),
          label: const Text('Update Placement / Internship Details'),
        ),
        const SizedBox(height: 7),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Student Report')),
                body: Padding(
                  padding: const EdgeInsets.all(18),
                  child: AdvancedReportsScreen(
                    user: actor,
                    repository: repository,
                  ),
                ),
              ),
            ),
          ),
          icon: const Icon(Icons.summarize_outlined, size: 15),
          label: const Text('Generate Student Report'),
        ),
        if (profile.coordinatorRemarks.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Remarks',
            style: TextStyle(
              fontSize: AppTheme.fontCaption,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.coordinatorRemarks,
            style: const TextStyle(
              fontSize: AppTheme.fontCaption,
              color: AppTheme.muted,
            ),
          ),
        ],
      ],
    ),
  );
}

String _displayValue(String? value, {String fallback = 'Unavailable'}) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}
