import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_theme.dart';
import '../models/app_feature.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../models/workflow_models.dart';
import '../services/practicum_repository.dart';
import 'workflow_shared.dart';

class StudentDashboardScreen extends StatelessWidget {
  const StudentDashboardScreen({
    super.key,
    required this.user,
    required this.repository,
    this.onNavigate,
  });
  final AppUser user;
  final PracticumRepository repository;
  final ValueChanged<AppFeature>? onNavigate;

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      WorkspaceHeader(
        title: 'Dashboard',
        subtitle: DateFormat.yMMMMEEEEd().format(DateTime.now()),
      ),
      const SizedBox(height: 22),
      StreamBuilder<List<RequirementDefinition>>(
        stream: repository.watchRequirementDefinitions(),
        builder: (context, definitionsSnapshot) =>
            StreamBuilder<List<RequirementRecord>>(
              stream: repository.watchRequirements(user),
              builder: (context, snapshot) {
                if (snapshot.hasError || definitionsSnapshot.hasError) {
                  return const Text(
                    'Document totals are unavailable. Open your checklist to try again.',
                  );
                }
                if (!snapshot.hasData || !definitionsSnapshot.hasData) {
                  return const LinearProgressIndicator();
                }
                final definitions = definitionsSnapshot.data!
                    .where(
                      (item) =>
                          item.active &&
                          (item.program == 'All Programs' ||
                              item.program == user.program),
                    )
                    .toList();
                final records = [...snapshot.data!]
                  ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
                final latest = <RequirementRecord>[];
                for (final definition in definitions) {
                  final match = records
                      .where(
                        (record) =>
                            record.definitionId == definition.id ||
                            record.title.toLowerCase() ==
                                definition.title.toLowerCase(),
                      )
                      .firstOrNull;
                  if (match != null) latest.add(match);
                }
                final verified = latest
                    .where((item) => item.status == ReviewStatus.verified)
                    .length;
                final attention = latest
                    .where(
                      (item) =>
                          item.status == ReviewStatus.rejected ||
                          item.status == ReviewStatus.needsRevision,
                    )
                    .length;
                final pending = latest
                    .where(
                      (item) =>
                          item.status == ReviewStatus.pending ||
                          item.status == ReviewStatus.underReview,
                    )
                    .length;
                return DashboardStatGrid(
                  cards: [
                    StatCard(
                      label: 'Required documents',
                      value: '${definitions.length}',
                      icon: Icons.fact_check_outlined,
                    ),
                    StatCard(
                      label: 'Verified',
                      value: '$verified',
                      icon: Icons.check_circle_outline,
                      color: AppTheme.success,
                    ),
                    StatCard(
                      label: 'Awaiting review',
                      value: '$pending',
                      icon: Icons.schedule_outlined,
                      color: AppTheme.purple,
                    ),
                    StatCard(
                      label: 'Needs attention',
                      value: '$attention',
                      icon: Icons.error_outline,
                      color: AppTheme.warning,
                    ),
                  ],
                );
              },
            ),
      ),
      const SizedBox(height: 18),
      DashboardWelcome(title: 'Welcome, ${user.displayName.split(' ').first}'),
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, constraints) {
          final tasks = SectionCard(
            title: 'Your next steps',
            child: Column(
              children: [
                _DashboardTask(
                  icon: Icons.description_outlined,
                  title: 'Manage your documents',
                  description:
                      'Check instructions, submit requirements, and respond to coordinator feedback.',
                  action: 'Open submissions',
                  onTap: onNavigate == null
                      ? null
                      : () => onNavigate!(AppFeature.repository),
                ),
                const Divider(height: 32),
                _DashboardTask(
                  icon: Icons.punch_clock_outlined,
                  title: 'Record your attendance',
                  description:
                      'Sign in for your scheduled shift and keep track of approved hours.',
                  action: 'Open DTR',
                  onTap: onNavigate == null
                      ? null
                      : () => onNavigate!(AppFeature.dtr),
                ),
                const Divider(height: 32),
                _DashboardTask(
                  icon: Icons.track_changes_outlined,
                  title: 'Follow your internship progress',
                  description:
                      'See your current stage, document deadlines, and evaluation status.',
                  action: 'View progress',
                  onTap: onNavigate == null
                      ? null
                      : () => onNavigate!(AppFeature.statusTracker),
                ),
              ],
            ),
          );
          final updates = StreamBuilder<List<NotificationRecord>>(
            stream: repository.watchNotifications(user),
            builder: (context, snapshot) {
              final notices = (snapshot.data ?? const <NotificationRecord>[])
                  .where((notice) => notice.active)
                  .take(4)
                  .toList();
              return SectionCard(
                title: 'Latest updates',
                trailing: TextButton(
                  onPressed: onNavigate == null
                      ? null
                      : () => onNavigate!(AppFeature.notifications),
                  child: const Text('View all'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snapshot.hasError)
                      const Text(
                        'Updates are unavailable. Open Notifications to try again.',
                      )
                    else if (!snapshot.hasData)
                      const LinearProgressIndicator()
                    else if (notices.isEmpty)
                      const Text(
                        'You’re all caught up. New internship updates will appear here.',
                      )
                    else
                      for (var index = 0; index < notices.length; index++) ...[
                        if (index > 0) const Divider(height: 28),
                        Text(
                          notices[index].title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          notices[index].message,
                          style: const TextStyle(
                            color: AppTheme.muted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat.MMMd().add_jm().format(
                            notices[index].deliveryTime,
                          ),
                          style: const TextStyle(
                            color: AppTheme.muted,
                            fontSize: AppTheme.fontCaption,
                          ),
                        ),
                      ],
                  ],
                ),
              );
            },
          );
          if (constraints.maxWidth < 900) {
            return Column(
              children: [tasks, const SizedBox(height: 20), updates],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: tasks),
              const SizedBox(width: 20),
              Expanded(flex: 4, child: updates),
            ],
          );
        },
      ),
    ],
  );
}

class _DashboardTask extends StatelessWidget {
  const _DashboardTask({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String description;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppTheme.blue, size: 24),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: AppTheme.muted, height: 1.5),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    ],
  );
}
