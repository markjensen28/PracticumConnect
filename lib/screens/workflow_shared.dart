import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';
import '../core/ssu_brand.dart';
import '../models/records.dart';
import '../services/practicum_repository.dart';

class WorkflowPage extends StatelessWidget {
  const WorkflowPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.eyebrow,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final page = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHeader(title: title, subtitle: subtitle, actions: actions),
          const SizedBox(height: 22),
          Expanded(child: child),
        ],
      );

      if (constraints.hasBoundedHeight) return page;

      final screenHeight = MediaQuery.sizeOf(context).height;
      final fallbackHeight = screenHeight > 540 ? screenHeight - 116 : 440.0;
      return SizedBox(height: fallbackHeight, child: page);
    },
  );
}

class WorkspaceHeader extends StatelessWidget {
  const WorkspaceHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      final heading = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              header: true,
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: compact ? 27 : 34,
                  height: 1.16,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      );

      if (actions.isEmpty) {
        return Align(alignment: Alignment.centerLeft, child: heading);
      }

      final controls = Wrap(
        alignment: constraints.maxWidth < 820
            ? WrapAlignment.start
            : WrapAlignment.end,
        spacing: 10,
        runSpacing: 10,
        children: actions,
      );

      if (constraints.maxWidth < 820) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [heading, const SizedBox(height: 14), controls],
        );
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: heading),
          const SizedBox(width: 22),
          Flexible(
            child: Align(alignment: Alignment.topRight, child: controls),
          ),
        ],
      );
    },
  );
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: padding == EdgeInsets.zero
                  ? const EdgeInsets.fromLTRB(18, 12, 12, 0)
                  : EdgeInsets.zero,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Semantics(
                          container: true,
                          header: true,
                          child: Text(
                            title!,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppTheme.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 17,
                                ),
                          ),
                        ),
                        if (subtitle != null &&
                            subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: AppTheme.fontSmall,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.compact = false,
    this.fontSize,
  });
  final String label;
  final bool compact;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final normalized = label.toLowerCase();
    final color = normalized.contains('reject') || normalized.contains('expire')
        ? AppTheme.danger
        : normalized == 'for verification' || normalized.contains('review')
        ? AppTheme.purple
        : normalized.contains('revision') ||
              normalized.contains('near') ||
              normalized.contains('renew') ||
              normalized.contains('pending') ||
              normalized.contains('not submitted')
        ? AppTheme.warning
        : normalized == 'verified' ||
              normalized == 'approved' ||
              normalized == 'active' ||
              normalized == 'completed' ||
              normalized == 'passed' ||
              normalized.startsWith('ongoing')
        ? AppTheme.success
        : AppTheme.muted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: fontSize == null || fontSize! < AppTheme.fontCaption
                ? AppTheme.fontCaption
                : fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppTheme.blue,
    this.caption,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? caption;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 220;
      return Card(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: caption == null ? 96 : 116),
          child: Padding(
            padding: EdgeInsets.all(compact ? 11 : 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: compact ? 38 : 54,
                  height: compact ? 38 : 54,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .105),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: compact ? 20 : 26),
                ),
                SizedBox(width: compact ? 9 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: AppTheme.navy,
                          fontSize: compact
                              ? AppTheme.fontCaption
                              : AppTheme.fontSmall,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppTheme.navy,
                          fontSize: compact ? 25 : 30,
                          fontWeight: FontWeight.w800,
                          height: 1.08,
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          caption!,
                          style: TextStyle(
                            color: color,
                            fontSize: AppTheme.fontCaption,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class DashboardStatGrid extends StatelessWidget {
  const DashboardStatGrid({super.key, required this.cards});

  final List<StatCard> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 14.0;
      final columns = constraints.maxWidth >= 880
          ? 4
          : constraints.maxWidth >= 336
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    },
  );
}

class DashboardWelcome extends StatelessWidget {
  const DashboardWelcome({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      return Card(
        color: AppTheme.surfaceBlue,
        child: Stack(
          children: [
            Positioned.fill(
              left: constraints.maxWidth * (compact ? .36 : .52),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/ssu-photo.jpg',
                    alignment: const Alignment(.65, -.55),
                    excludeFromSemantics: true,
                    fit: BoxFit.cover,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.surfaceBlue, Color(0x8AEAF2FF)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 15 : 23,
                vertical: compact ? 16 : 18,
              ),
              child: Row(
                children: [
                  SsuSeal(size: compact ? 54 : 67, decorative: true),
                  SizedBox(width: compact ? 13 : 18),
                  SizedBox(
                    height: compact ? 40 : 48,
                    child: const VerticalDivider(
                      width: 2,
                      thickness: 2,
                      color: AppTheme.gold,
                    ),
                  ),
                  SizedBox(width: compact ? 13 : 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: AppTheme.navy,
                                fontSize: compact ? 19 : 23,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Samar State University',
                          style: TextStyle(
                            color: AppTheme.deepBlue,
                            fontSize: AppTheme.fontSmall,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class WorkspaceMetrics extends StatelessWidget {
  const WorkspaceMetrics({super.key, required this.items});

  final List<({String label, int value, IconData icon, Color color})> items;

  @override
  Widget build(BuildContext context) => Card(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            items.length <= 2 ||
                constraints.maxWidth >= (items.length == 4 ? 640 : 320)
            ? items.length
            : 2;
        final compact = constraints.maxWidth / columns < 150;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < items.length; start += columns) ...[
              if (start > 0) const Divider(height: 1),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (column, item)
                        in items.skip(start).take(columns).indexed)
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: BorderDirectional(
                              start: column == 0
                                  ? BorderSide.none
                                  : const BorderSide(color: AppTheme.border),
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 10 : 16,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 4,
                              children: [
                                Row(
                                  spacing: 8,
                                  children: [
                                    Icon(
                                      item.icon,
                                      color: item.color,
                                      size: 18,
                                    ),
                                    Flexible(
                                      child: Text(
                                        '${item.value}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  item.label,
                                  style: const TextStyle(color: AppTheme.muted),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    for (
                      var empty = items.length - start;
                      empty < columns;
                      empty++
                    )
                      const Spacer(),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class WorkspaceFilterBar extends StatelessWidget {
  const WorkspaceFilterBar({
    super.key,
    required this.search,
    required this.fields,
    required this.onReset,
    required this.canReset,
    this.inlineAction,
  });

  final Widget search;
  final List<Widget> fields;
  final VoidCallback onReset;
  final bool canReset;
  final Widget? inlineAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 10,
          children: [
            Expanded(flex: 3, child: search),
            if (constraints.maxWidth >= 730) ...[
              for (final field in fields) Expanded(flex: 2, child: field),
              if (inlineAction case final action?) action,
              TextButton.icon(
                onPressed: canReset ? onReset : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 17),
                label: const Text('Reset'),
              ),
            ] else
              OutlinedButton.icon(
                onPressed: () => _showFilters(context),
                icon: const Icon(Icons.tune_rounded, size: 17),
                label: const Text('Filters'),
              ),
          ],
        ),
      ),
    ),
  );

  void _showFilters(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Filters'),
        scrollable: true,
        content: SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: fields,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              onReset();
              Navigator.pop(dialogContext);
            },
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class WorkspaceTabs extends StatelessWidget {
  const WorkspaceTabs({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.counts,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<int>? counts;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppTheme.border)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index == selectedIndex;
          final count = counts != null && index < counts!.length
              ? counts![index]
              : null;
          return Semantics(
            selected: active,
            button: true,
            child: InkWell(
              onTap: () => onSelected(index),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: active ? AppTheme.surfaceBlue : null,
                  border: Border(
                    bottom: BorderSide(
                      color: active ? AppTheme.blue : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      labels[index],
                      style: TextStyle(
                        color: active ? AppTheme.deepBlue : AppTheme.muted,
                        fontSize: AppTheme.fontSmall,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (count != null && count > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '$count',
                        style: const TextStyle(
                          fontSize: AppTheme.fontCaption,
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    ),
  );
}

class WorkspaceTable extends StatelessWidget {
  const WorkspaceTable({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: constraints.hasBoundedWidth ? constraints.maxWidth : 0,
        ),
        child: child,
      ),
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.labelWidth = 104});
  final String label;
  final String value;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.muted,
              fontSize: AppTheme.fontSmall,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isEmpty ? '—' : value,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: AppTheme.fontSmall,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyWorkflowState extends StatelessWidget {
  const EmptyWorkflowState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppTheme.surfaceBlue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 28, color: AppTheme.blue),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: AppTheme.fontSmall,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String shortDate(DateTime? value) =>
    value == null ? '—' : DateFormat.yMMMd().format(value);

Future<void> openStorageDocument(
  BuildContext context,
  PracticumRepository repository,
  String? storagePath,
) async {
  if (storagePath == null || storagePath.isEmpty) return;
  if (!AppConfig.hasSupabaseConfig) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppConfig.missingSupabaseMessage),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    return;
  }
  try {
    final url = await repository.createDownloadUrl(storagePath);
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
    if (!launched) throw StateError('The browser could not open the file.');
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open document: $error')),
      );
    }
  }
}

Color reviewStatusColor(ReviewStatus status) => switch (status) {
  ReviewStatus.verified => AppTheme.success,
  ReviewStatus.needsRevision => AppTheme.warning,
  ReviewStatus.rejected => AppTheme.danger,
  ReviewStatus.underReview => AppTheme.purple,
  ReviewStatus.pending => AppTheme.blue,
};
