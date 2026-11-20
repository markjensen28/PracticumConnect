import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:practicum_connect/models/app_user.dart';
import 'package:practicum_connect/models/records.dart';
import 'package:practicum_connect/models/workflow_models.dart';
import 'package:practicum_connect/services/practicum_repository.dart';

class FailingFirestore extends FakeFirebaseFirestore {
  bool failStageRead = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    if (failStageRead && path == 'requirement_definitions') {
      throw StateError('Simulated unavailable status dependency');
    }
    return super.collection(path);
  }
}

void main() {
  const staff = AppUser(
    uid: 'staff',
    email: 'staff@example.invalid',
    displayName: 'Staff',
    role: UserRole.coordinator,
  );
  const student = AppUser(
    uid: 'student',
    email: 'student@example.invalid',
    displayName: 'Student',
    role: UserRole.student,
    coordinatorId: 'staff',
  );
  late FailingFirestore db;
  late PracticumRepository repository;
  setUp(() async {
    db = FailingFirestore();
    repository = PracticumRepository(firestore: db);
    await db.doc('users/student').set({
      'role': 'student',
      'coordinatorId': 'staff',
      'academicYear': '2026-2027',
      'program': 'Test',
    });
    await db.doc('internship_profiles/student').set({
      'status': 'For Verification',
      'coordinatorId': 'staff',
      'academicYear': '2026-2027',
      'placementStatus': 'Unassigned',
      'archived': false,
      'requiredHours': 8,
    });
    await db.doc('requirement_definitions/cv').set({
      'title': 'CV',
      'active': true,
    });
    await db.doc('requirements/cv').set({
      'studentId': 'student',
      'coordinatorId': 'staff',
      'academicYear': '2026-2027',
      'definitionId': 'cv',
      'title': 'CV',
      'status': 'pending',
      'archived': false,
      'submittedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
    });
    await db.doc('dtr_entries/day').set({
      'studentId': 'student',
      'coordinatorId': 'staff',
      'academicYear': '2026-2027',
      'status': 'pending',
      'archived': false,
      'date': Timestamp.fromDate(DateTime(2026, 11, 1)),
      'breakMinutes': 0,
      'timeIn': Timestamp.fromDate(DateTime(2026, 11, 1, 8)),
      'timeOut': Timestamp.fromDate(DateTime(2026, 11, 1, 16)),
    });
    await db.doc('supervisor_evaluations/evaluation').set({
      'studentId': 'student',
      'coordinatorId': 'staff',
      'academicYear': '2026-2027',
      'status': 'submitted',
      'archived': false,
    });
  });
  Future<void> reviewRequirement() => repository.updateRequirementStatus(
    requirementId: 'cv',
    status: ReviewStatus.verified,
    remarks: 'Approved',
    reviewer: staff,
  );
  Future<void> reviewDtr() => repository.updateDtrStatus(
    recordId: 'day',
    status: ReviewStatus.verified,
    remarks: 'Approved',
    reviewer: staff,
  );
  Future<String> stage() async =>
      (await db.doc('internship_profiles/student').get()).get('status')
          as String;
  Future<int> count(String collection) async =>
      (await db.collection(collection).get()).size;

  test(
    'review calculates from proposed approval and retries without duplicate feedback',
    () async {
      await reviewRequirement();
      expect(await stage(), 'Ready for Deployment');
      expect(await count('notifications'), 2);
      expect(await count('activity_logs'), 1);
      await reviewRequirement();
      expect(await count('notifications'), 2);
      expect(await count('activity_logs'), 1);
    },
  );
  test(
    'DTR approval contributes hours immediately and retry is idempotent',
    () async {
      await db.doc('requirements/cv').update({'status': 'verified'});
      await db.doc('internship_profiles/student').update({
        'placementStatus': 'Confirmed',
      });
      await reviewDtr();
      expect(await stage(), 'Completed');
      await reviewDtr();
      expect(await count('notifications'), 2);
      expect(await count('activity_logs'), 1);
    },
  );
  for (final kind in ['requirement', 'DTR']) {
    test(
      '$kind synchronization failure leaves review and feedback untouched',
      () async {
        db.failStageRead = true;
        await expectLater(
          kind == 'requirement' ? reviewRequirement() : reviewDtr(),
          throwsStateError,
        );
        expect(
          (await db
                  .doc(
                    kind == 'requirement'
                        ? 'requirements/cv'
                        : 'dtr_entries/day',
                  )
                  .get())
              .get('status'),
          'pending',
        );
        expect(await count('notifications'), 0);
        expect(await count('activity_logs'), 0);
      },
    );
  }
  Future<void> saveProfile() => repository.saveInternshipProfile(
    actor: staff,
    student: student,
    program: 'Test',
    yearLevel: '4',
    academicYear: '2026-2027',
    profile: const InternshipProfileRecord(
      studentId: 'student',
      coordinatorId: 'staff',
      placementStatus: 'Confirmed',
      requiredHours: 8,
      companyName: 'New company',
      workDays: [1, 2, 3, 4, 5],
    ),
  );
  test(
    'profile save uses proposed placement and saves one audit on retry',
    () async {
      await db.doc('requirements/cv').update({'status': 'verified'});
      await saveProfile();
      expect(await stage(), 'Ongoing Internship');
      expect(
        (await db.doc('internship_profiles/student').get()).get('companyName'),
        'New company',
      );
      await saveProfile();
      expect(await count('activity_logs'), 1);
      expect(await count('notifications'), 1);
    },
  );
  test(
    'profile synchronization failure leaves profile and user unchanged',
    () async {
      db.failStageRead = true;
      await expectLater(saveProfile(), throwsStateError);
      expect(
        (await db.doc('internship_profiles/student').get()).get(
          'placementStatus',
        ),
        'Unassigned',
      );
      expect(
        (await db.doc('users/student').get()).data()!.containsKey('yearLevel'),
        false,
      );
      expect(await count('activity_logs'), 0);
    },
  );
  test('unassigned coordinator cannot review', () async {
    await db.doc('users/student').update({'coordinatorId': 'other'});
    await expectLater(reviewRequirement(), throwsStateError);
    expect(await count('activity_logs'), 0);
  });
}
