import 'package:practicum_connect/models/app_user.dart';
import 'package:practicum_connect/models/records.dart';
import 'package:practicum_connect/models/workflow_models.dart';
import 'package:practicum_connect/services/practicum_repository.dart';

const student = AppUser(
  uid: 'student',
  email: 'student@example.test',
  displayName: 'Alexandra Student',
  role: UserRole.student,
  studentNumber: '2026-12345',
  program: 'College of Arts and Sciences',
  academicYear: '2026-2027',
  coordinatorId: 'coordinator',
);

Stream<T> fixtureStream<T>(T value) => Stream<T>.multi((controller) {
  controller.add(value);
  controller.close();
}, isBroadcast: true);

class LayoutRepository extends PracticumRepository {
  @override
  Stream<int> watchReminderHours(AppUser user) => fixtureStream(72);

  final definitions = fixtureStream([
    RequirementDefinition(
      id: 'cv',
      title: 'Curriculum vitae and professional experience',
      description: 'Prepare a current CV for your internship application.',
      instructions: 'Upload your current document.',
      category: 'Deployment',
      dueDate: DateTime(2027, 1, 20),
    ),
    RequirementDefinition(
      id: 'resume',
      title: 'Resume',
      description: 'Your application resume.',
      instructions: 'Upload your resume.',
      category: 'Deployment',
      dueDate: DateTime(2027, 1, 20),
    ),
  ]);
  final requirements = fixtureStream([
    RequirementRecord(
      id: 'submission',
      definitionId: 'resume',
      studentId: 'student',
      studentName: 'Alexandra Student',
      title: 'Resume',
      status: ReviewStatus.rejected,
      submittedAt: DateTime(2026, 11, 11),
      remarks: 'Please include your updated contact details.',
    ),
  ]);
  final notifications = fixtureStream([
    NotificationRecord(
      id: 'notice',
      title: 'Your resume needs a correction before verification',
      message:
          'Your coordinator reviewed your resume. Please update your contact details and submit the corrected document.',
      createdAt: DateTime(2026, 11, 11),
      targetRole: 'all',
      type: 'document_feedback',
    ),
  ]);
  final students = fixtureStream([student]);
  final profiles = fixtureStream([
    const InternshipProfileRecord(studentId: 'student'),
  ]);
  final profile = fixtureStream<InternshipProfileRecord?>(
    const InternshipProfileRecord(studentId: 'student'),
  );
  final dtr = fixtureStream([
    DtrRecord(
      id: 'shift',
      breakMinutes: 0,
      status: ReviewStatus.pending,
      studentId: 'student',
      studentName: 'Alexandra Student',
      date: DateTime(2026, 11, 11),
      timeIn: DateTime(2026, 11, 11, 8),
      timeOut: DateTime(2026, 11, 11, 17),
    ),
  ]);
  final moas = fixtureStream<List<MoaRecord>>([]);
  final activity = fixtureStream<List<ActivityLogRecord>>([]);
  final statuses = fixtureStream<List<String>>([]);

  @override
  Stream<List<RequirementDefinition>> watchRequirementDefinitions() =>
      definitions;
  @override
  Stream<List<RequirementRecord>> watchRequirements(AppUser user) =>
      requirements;
  @override
  Stream<List<NotificationRecord>> watchNotifications(AppUser user) =>
      notifications;
  @override
  Stream<List<AppUser>> watchStudentsFor(AppUser actor) => students;
  @override
  Stream<List<InternshipProfileRecord>> watchInternshipProfilesFor(
    AppUser actor,
  ) => profiles;
  @override
  Stream<InternshipProfileRecord?> watchInternshipProfile(String studentId) =>
      profile;
  @override
  Stream<List<DtrRecord>> watchDtr(AppUser user) => dtr;
  @override
  Stream<List<MoaRecord>> watchMoas() => moas;
  @override
  Stream<List<ActivityLogRecord>> watchActivityLogs({AppUser? actor}) =>
      activity;
  @override
  Stream<List<String>> watchStudentEvaluationStatuses(
    String studentId,
    String? academicYear,
  ) => statuses;
}
