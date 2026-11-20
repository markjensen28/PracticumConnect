import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:practicum_connect/core/app_theme.dart';
import 'package:practicum_connect/models/app_feature.dart';
import 'package:practicum_connect/models/app_user.dart';
import 'package:practicum_connect/screens/account_settings_screen.dart';
import 'package:practicum_connect/screens/coordinator_dashboard_screen.dart';
import 'package:practicum_connect/screens/document_workflow_screens.dart';
import 'package:practicum_connect/screens/module_screens.dart';
import 'package:practicum_connect/screens/notification_panel_screen.dart';
import 'package:practicum_connect/screens/student_dashboard_screen.dart';
import 'support/workspace_fixture.dart';

void main() {
  for (final width in [390.0, 1024.0, 1600.0]) {
    testWidgets('workspace layouts fit ${width.toInt()}px with larger text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = LayoutRepository();
      final pages = <Widget>[
        StudentDashboardScreen(user: student, repository: repository),
        StudentStatusTrackerScreen(user: student, repository: repository),
        StudentRequirementsChecklistScreen(
          user: student,
          repository: repository,
        ),
        DocumentSubmissionBinScreen(user: student, repository: repository),
        StudentNotificationPanelScreen(user: student, repository: repository),
        DtrScreen(user: student, repository: repository),
        AccountSettingsScreen(user: student, repository: repository),
        for (final role in [UserRole.coordinator, UserRole.admin])
          CoordinatorDashboardScreen(
            user: AppUser(
              uid: 'coordinator',
              email: 'staff@example.test',
              displayName: 'Program Coordinator',
              role: role,
            ),
            repository: repository,
          ),
      ];
      for (final page in pages) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.2)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(padding: const EdgeInsets.all(16), child: page),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.runtimeType} at $width',
        );
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('student dashboard links navigate to the requested module', (
    tester,
  ) async {
    AppFeature? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StudentDashboardScreen(
            user: student,
            repository: LayoutRepository(),
            onNavigate: (feature) => selected = feature,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open submissions'));
    expect(selected, AppFeature.repository);
    expect(find.text('Your access'), findsNothing);
    expect(find.text('Accessible modules'), findsNothing);
  });
}
