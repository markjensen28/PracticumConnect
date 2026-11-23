import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../services/practicum_repository.dart';
import 'workflow_shared.dart';

class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({
    super.key,
    required this.user,
    required this.repository,
  });

  final AppUser user;
  final PracticumRepository repository;

  @override
  Widget build(BuildContext context) => WorkflowPage(
    title: 'Settings',
    subtitle: 'Manage your Practicum Connect account and security options.',
    eyebrow: 'Home  ›  Settings',
    child: ListView(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 820;
            final account = SectionCard(
              title: 'Account Information',
              child: Column(
                children: [
                  _SettingsRow(label: 'Name', value: user.displayName),
                  _SettingsRow(label: 'Email', value: user.email),
                  _SettingsRow(label: 'Role', value: user.role.label),
                  if (user.studentNumber?.isNotEmpty == true)
                    _SettingsRow(
                      label: 'Student ID',
                      value: user.studentNumber!,
                    ),
                  if (user.staffId?.isNotEmpty == true)
                    _SettingsRow(label: 'Staff ID', value: user.staffId!),
                  if (user.role == UserRole.coordinator)
                    _SettingsRow(
                      label: 'Program',
                      value: user.casProgram ?? 'Program not set',
                    )
                  else if (user.program?.isNotEmpty == true)
                    _SettingsRow(label: 'Program', value: user.program!),
                  if (user.college case final college?)
                    _SettingsRow(label: 'College', value: college)
                  else if (user.department?.isNotEmpty == true)
                    _SettingsRow(label: 'Department', value: user.department!),
                  if (user.academicYear?.isNotEmpty == true)
                    _SettingsRow(
                      label: 'Academic Year',
                      value: user.academicYear!,
                      showDivider: false,
                    ),
                ],
              ),
            );
            final preferences = SectionCard(
              title: 'Preferences & Security',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.light_mode_outlined,
                          color: AppTheme.blue,
                          size: 20,
                        ),
                        SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Light appearance',
                                style: TextStyle(
                                  color: AppTheme.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: AppTheme.fontSmall,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Practicum Connect uses a clean light interface for consistent school deployment.',
                                style: TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: AppTheme.fontCaption,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (user.role != UserRole.admin)
                    StreamBuilder<int>(
                      stream: repository.watchReminderHours(user),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text(
                            'Unable to load reminder preferences.',
                          );
                        }
                        final hours = snapshot.data;
                        if (hours == null) {
                          return const LinearProgressIndicator();
                        }
                        final student = user.role == UserRole.student;
                        final amount = hours % 24 == 0
                            ? '${hours ~/ 24} day${hours == 24 ? '' : 's'}'
                            : '$hours hour${hours == 1 ? '' : 's'}';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            student
                                ? 'Requirement deadline reminder'
                                : 'Pending verification reminder',
                          ),
                          subtitle: Text(
                            student
                                ? '$amount before the deadline'
                                : '$amount after submission',
                          ),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () => _editReminder(context, hours),
                        );
                      },
                    ),
                  OutlinedButton.icon(
                    onPressed: user.email.isEmpty
                        ? null
                        : () => _sendPasswordReset(context),
                    icon: const Icon(Icons.lock_reset_rounded, size: 17),
                    label: const Text('Send password reset email'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Account role and internship details are managed by authorized school personnel.',
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: AppTheme.fontCaption,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );

            if (stacked) {
              return Column(
                children: [account, const SizedBox(height: 12), preferences],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: account),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: preferences),
              ],
            );
          },
        ),
      ],
    ),
  );

  Future<void> _editReminder(BuildContext context, int initialHours) async {
    var days = initialHours % 24 == 0;
    var amount = '${days ? initialHours ~/ 24 : initialHours}';
    String? error;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(
            user.role == UserRole.student
                ? 'Remind me before the deadline'
                : 'Remind me after submission',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: amount,
                onChanged: (value) => amount = value,
                enabled: !saving,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Time',
                  errorText: error,
                ),
              ),
              DropdownButtonFormField<bool>(
                initialValue: days,
                decoration: const InputDecoration(labelText: 'Unit'),
                items: const [
                  DropdownMenuItem(value: true, child: Text('Days')),
                  DropdownMenuItem(value: false, child: Text('Hours')),
                ],
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) {
                          update(() {
                            days = value;
                            error = null;
                          });
                        }
                      },
              ),
            ],
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
                      final hours =
                          (int.tryParse(amount.trim()) ?? 0) * (days ? 24 : 1);
                      if (hours < 1 || hours > 720) {
                        update(
                          () => error =
                              'Enter a whole number from 1 to ${days ? 30 : 720}.',
                        );
                        return;
                      }
                      update(() => saving = true);
                      try {
                        await repository.saveReminderHours(user, hours);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (context.mounted) {
                          update(() {
                            saving = false;
                            error = 'Unable to save reminder preference.';
                          });
                        }
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPasswordReset(BuildContext context) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: user.email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to ${user.email}.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Unable to send reset email.')),
      );
    }
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: AppTheme.fontCaption,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: AppTheme.fontSmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
      if (showDivider) const Divider(height: 1),
    ],
  );
}
