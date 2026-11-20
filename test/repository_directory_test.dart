import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:practicum_connect/models/app_user.dart';
import 'package:practicum_connect/models/records.dart';
import 'package:practicum_connect/screens/document_workflow_screens.dart';

import 'support/workspace_fixture.dart';

class FolderRepository extends LayoutRepository {
  final submissions = StreamController<List<RequirementRecord>>();
  @override
  Stream<List<RequirementRecord>> watchRepositoryDocuments(AppUser user) =>
      submissions.stream;
  @override
  Stream<List<AppUser>> watchStudentsFor(AppUser actor) => fixtureStream([
    for (final id in ['101', '102'])
      AppUser(
        uid: id,
        displayName: 'Kim',
        email: '',
        role: UserRole.student,
        department: 'Computing',
        section: 'BSIT A',
        studentNumber: id,
      ),
  ]);
}

RequirementRecord submission(String file, String studentId) =>
    RequirementRecord(
      id: file,
      studentId: studentId,
      studentName: 'Kim',
      title: file,
      fileName: file,
      status: ReviewStatus.pending,
      submittedAt: DateTime(2026),
      category: 'Requirements',
    );

void main() {
  for (final width in [390.0, 1600.0]) {
    testWidgets('folder selection follows live submissions at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FolderRepository();
      addTearDown(repository.submissions.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentRepositoryScreen(
              user: const AppUser(
                uid: 'staff',
                displayName: 'Staff',
                email: '',
                role: UserRole.coordinator,
              ),
              repository: repository,
            ),
          ),
        ),
      );
      repository.submissions.add([submission('Other.pdf', '102')]);
      await tester.pumpAndSettle();
      if (width < 600) await tester.tap(find.textContaining('Folders /'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Computing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BSIT A'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('101').first);
      await tester.pumpAndSettle();
      if (width < 600) await tester.tap(find.text('Show documents'));
      await tester.pumpAndSettle();
      expect(find.text('No matching documents'), findsOneWidget);
      repository.submissions.add([
        submission('My file.pdf', '101'),
        submission('Other.pdf', '102'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('My file.pdf'), findsWidgets);
      expect(find.text('Other.pdf'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
