import 'dart:async';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fake_async/fake_async.dart';
import 'package:practicum_connect/screens/account_settings_screen.dart';
import 'package:practicum_connect/services/practicum_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:practicum_connect/models/app_user.dart';
import 'package:practicum_connect/models/records.dart';
import 'package:practicum_connect/models/workflow_models.dart';
import 'package:practicum_connect/models/requirement_compliance.dart';
import 'package:practicum_connect/services/notification_schedule.dart';

void main() {
  testWidgets('student can change the default to six hours in Settings', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    const user = AppUser(
      uid: 'intern',
      email: '',
      displayName: 'Intern',
      role: UserRole.student,
    );
    final ref = db.collection('users').doc(user.uid);
    await ref.set({'role': 'student'});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountSettingsScreen(
            user: user,
            repository: PracticumRepository(firestore: db),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preference = find.text('3 days before the deadline');
    await tester.ensureVisible(preference);
    await tester.tap(preference);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Days'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '6');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await ref.get()).get('reminderHours'), 6);
    expect(find.text('6 hours before the deadline'), findsOneWidget);
  });
  test(
    'one verified assignment among ten, including legacy and duplicate records',
    () {
      const student = AppUser(
        uid: 's',
        email: '',
        displayName: 'Student',
        role: UserRole.student,
        program: 'Arts',
        academicYear: '2026-2027',
      );
      RequirementDefinition definition(
        int i, {
        String program = 'Arts',
        bool active = true,
        String? title,
      }) => RequirementDefinition(
        id: 'd$i',
        title: title ?? 'Form $i',
        category: 'General',
        description: '',
        instructions: '',
        dueDate: DateTime(2026),
        program: program,
        active: active,
      );
      final defs = [
        for (var i = 0; i < 10; i++) definition(i),
        definition(10, program: 'Science'),
        definition(11, active: false),
      ];
      RequirementRecord record(
        String? def,
        String title,
        int order, {
        String year = '2026-2027',
        ReviewStatus status = ReviewStatus.verified,
        bool archived = false,
      }) => RequirementRecord(
        id: 'r$order',
        definitionId: def,
        title: title,
        studentId: 's',
        studentName: 'Student',
        academicYear: year,
        status: status,
        archived: archived,
        submittedAt: DateTime(2026, 1, order),
      );
      final records = [
        record(null, ' FORM 0 ', 1),
        record('d0', 'Form 0', 2),
        record('d1', 'Form 1', 3),
        record('d1', 'Form 1', 4, status: ReviewStatus.needsRevision),
        record('d2', 'Form 2', 5, year: '2025-2026'),
        record('d3', 'Form 3', 6, archived: true),
        record('d10', 'Form 0', 7),
        record('d11', 'Form 11', 8),
      ];
      expect(
        RequirementCompliance.forStudent(student, defs, records).label,
        '1 / 10',
      );
      expect(
        RequirementCompliance.forStudent(
          student,
          [definition(0), definition(1, title: 'Form 0')],
          [records.first],
        ).label,
        '0 / 2',
      );
      expect(
        RequirementCompliance.forStudent(student, [], records).label,
        'No requirements assigned',
      );
    },
  );
  test(
    'notice appears at its revised time without another database snapshot',
    () => fakeAsync((time) {
      final source = StreamController<List<NotificationRecord>>(sync: true);
      final start = DateTime.utc(2026, 11, 1);
      final seen = <List<NotificationRecord>>[];
      final sub = watchNotificationSchedule(
        source.stream,
        now: () => start.add(time.elapsed),
      ).listen(seen.add);
      NotificationRecord notice(int hours) => NotificationRecord(
        id: 'n',
        title: 'Due',
        message: '',
        createdAt: start,
        targetRole: 'all',
        scheduledFor: start.add(Duration(hours: hours)),
      );
      source.add([notice(1)]);
      time.flushMicrotasks();
      expect(seen.last, isEmpty);
      source.add([notice(2)]);
      time.elapse(const Duration(hours: 1));
      expect(seen.last, isEmpty);
      time.elapse(const Duration(hours: 1));
      expect(seen.last.single.id, 'n');
      unawaited(sub.cancel());
      time.flushMicrotasks();
      unawaited(source.close());
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 0);
    }),
  );
}
