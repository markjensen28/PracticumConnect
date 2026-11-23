import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ssu_brand.dart';
import '../models/app_feature.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../services/app_controller.dart';
import '../services/practicum_repository.dart';
import 'module_screens.dart';
import 'workspace_select_field.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppFeature _selected = AppFeature.dashboard;
  bool _navigationExpanded = true;
  late final Stream<List<NotificationRecord>> _notificationStream;

  @override
  void initState() {
    super.initState();
    _notificationStream = widget.controller.repository.watchNotifications(
      widget.controller.user!,
    );
  }

  Future<void> _openGlobalSearch() async {
    final user = widget.controller.user!;

    final feature = await showDialog<AppFeature>(
      context: context,
      builder: (_) => _GlobalSearchDialog(
        user: user,
        repository: widget.controller.repository,
      ),
    );

    if (!mounted || feature == null) return;

    setState(() => _selected = feature);
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.controller.user!;
    final features = RoleAccess.forRole(user.role).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1040;
        final navigation = _SideNavigation(
          features: features,
          selected: _selected,
          user: user,
          expanded: !desktop || _navigationExpanded,
          onSelected: (feature) {
            setState(() => _selected = feature);
            if (!desktop) Navigator.pop(context);
          },
        );

        final content = Scaffold(
          backgroundColor: AppTheme.background,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: _TopBar(
              user: user,
              notificationStream: _notificationStream,
              desktop: desktop,
              navigationExpanded: _navigationExpanded,
              onToggleNavigation: desktop
                  ? () => setState(
                      () => _navigationExpanded = !_navigationExpanded,
                    )
                  : null,
              onSearch: _openGlobalSearch,
              onNotifications:
                  RoleAccess.canAccess(user.role, AppFeature.notifications)
                  ? () => setState(() => _selected = AppFeature.notifications)
                  : null,
              onLogout: widget.controller.signOut,
            ),
          ),
          drawer: desktop
              ? null
              : Drawer(
                  width: 272,
                  backgroundColor: AppTheme.navy,
                  surfaceTintColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(),
                  child: navigation,
                ),
          body: LayoutBuilder(
            builder: (context, bodyConstraints) {
              final roomy = bodyConstraints.maxWidth >= 820;
              final horizontalPadding = roomy ? 28.0 : 16.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  roomy ? 26 : 20,
                  horizontalPadding,
                  roomy ? 28 : 18,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppTheme.contentMaxWidth,
                    ),
                    child: SizedBox.expand(
                      child: ModuleRouter(
                        feature: _selected,
                        user: user,
                        repository: widget.controller.repository,
                        onNavigate: (feature) =>
                            setState(() => _selected = feature),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (desktop)
              SizedBox(
                width: _navigationExpanded ? 250 : 72,
                child: navigation,
              ),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({required this.user, required this.repository});

  final AppUser user;
  final PracticumRepository repository;

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  late final Future<_GlobalSearchData> _data;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  Future<_GlobalSearchData> _loadData() async {
    final requirements = await widget.repository
        .watchRequirements(widget.user)
        .first;

    final students = widget.user.role.isStaff
        ? await widget.repository.watchStudentsFor(widget.user).first
        : const <AppUser>[];

    final partners = widget.user.role == UserRole.admin
        ? await widget.repository.watchPartnerInstitutions().first
        : const <PartnerInstitutionRecord>[];

    return _GlobalSearchData(
      students: students,
      requirements: requirements,
      partners: partners,
    );
  }

  List<_GlobalSearchResult> _buildResults(_GlobalSearchData data) {
    final query = _query.trim().toLowerCase();
    final results = <_GlobalSearchResult>[];

    for (final feature in RoleAccess.forRole(widget.user.role)) {
      final label = feature.labelForRole(widget.user.role);

      if (query.isEmpty || label.toLowerCase().contains(query)) {
        results.add(
          _GlobalSearchResult(
            title: label,
            subtitle: 'Open module',
            icon: feature.icon,
            feature: feature,
          ),
        );
      }
    }

    if (query.isEmpty) {
      return results;
    }

    for (final student in data.students) {
      final searchable =
          '${student.displayName} '
                  '${student.email} '
                  '${student.studentNumber ?? ''} '
                  '${student.program ?? ''} '
                  '${student.yearLevel ?? ''}'
              .toLowerCase();

      if (searchable.contains(query)) {
        results.add(
          _GlobalSearchResult(
            title: student.displayName,
            subtitle:
                '${student.studentNumber ?? 'No student number'} â€¢ '
                '${student.program ?? 'Program not set'}',
            icon: Icons.person_outline,
            feature: AppFeature.students,
          ),
        );
      }
    }

    for (final record in data.requirements) {
      final searchable =
          '${record.title} '
                  '${record.studentName} '
                  '${record.studentNumber ?? ''} '
                  '${record.fileName ?? ''} '
                  '${record.category} '
                  '${record.program ?? ''} '
                  '${record.institutionName ?? ''}'
              .toLowerCase();

      if (searchable.contains(query)) {
        results.add(
          _GlobalSearchResult(
            title: record.title,
            subtitle: widget.user.role == UserRole.student
                ? '${record.category} â€¢ ${record.status.label}'
                : '${record.studentName} â€¢ ${record.status.label}',
            icon: Icons.description_outlined,
            feature: widget.user.role == UserRole.student
                ? AppFeature.requirements
                : AppFeature.documentReview,
          ),
        );
      }
    }

    for (final partner in data.partners) {
      final searchable =
          '${partner.name} '
                  '${partner.address} '
                  '${partner.industryField} '
                  '${partner.institutionType} '
                  '${partner.contactName} '
                  '${partner.contactEmail} '
                  '${partner.programs.join(' ')}'
              .toLowerCase();

      if (searchable.contains(query)) {
        results.add(
          _GlobalSearchResult(
            title: partner.name,
            subtitle: [
              partner.industryField,
              partner.contactName,
            ].where((value) => value.isNotEmpty).join(' â€¢ '),
            icon: Icons.business_outlined,
            feature: AppFeature.moa,
          ),
        );
      }
    }

    return results.take(50).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.search_rounded),
          SizedBox(width: 10),
          Text('Search Practicum Connect'),
        ],
      ),
      content: SizedBox(
        width: 680,
        height: 500,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: switch (widget.user.role) {
                  UserRole.student =>
                    'Search requirements, documents, or modules',
                  UserRole.coordinator =>
                    'Search assigned interns, documents, or modules',
                  UserRole.admin =>
                    'Search students, documents, institutions, or modules',
                },
              ),
              onChanged: (value) {
                setState(() => _query = value);
              },
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<_GlobalSearchData>(
                future: _data,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Unable to search: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final results = _buildResults(snapshot.data!);

                  if (results.isEmpty) {
                    return const Center(
                      child: Text('No matching results found.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = results[index];

                      return ListTile(
                        leading: Icon(result.icon),
                        title: Text(result.title),
                        subtitle: result.subtitle.isEmpty
                            ? null
                            : Text(result.subtitle),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.of(context).pop(result.feature);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _GlobalSearchData {
  const _GlobalSearchData({
    required this.students,
    required this.requirements,
    required this.partners,
  });

  final List<AppUser> students;
  final List<RequirementRecord> requirements;
  final List<PartnerInstitutionRecord> partners;
}

class _GlobalSearchResult {
  const _GlobalSearchResult({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.feature,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final AppFeature feature;
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.user,
    required this.notificationStream,
    required this.desktop,
    required this.navigationExpanded,
    this.onToggleNavigation,
    required this.onSearch,
    required this.onNotifications,
    required this.onLogout,
  });

  final AppUser user;
  final Stream<List<NotificationRecord>> notificationStream;
  final bool desktop;
  final bool navigationExpanded;
  final VoidCallback? onToggleNavigation;
  final VoidCallback onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: Container(
        height: 64,
        padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Builder(
              builder: (context) => IconButton(
                tooltip: !desktop
                    ? 'Open navigation'
                    : navigationExpanded
                    ? 'Collapse navigation'
                    : 'Expand navigation',
                onPressed:
                    onToggleNavigation ??
                    () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded, color: AppTheme.navy),
              ),
            ),
            SizedBox(width: desktop ? 12 : 4),
            Expanded(
              child: Text(
                'Practicum Connect',
                maxLines: desktop ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.navy,
                  fontSize: desktop ? 17 : AppTheme.fontSmall,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            if (desktop) ...[
              OutlinedButton.icon(
                onPressed: onSearch,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceSoft,
                  foregroundColor: AppTheme.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: const BorderSide(color: AppTheme.border),
                ),
                icon: const Icon(Icons.search_rounded, size: 19),
                label: const Text('Search workspace'),
              ),
              const SizedBox(width: 10),
            ] else
              IconButton(
                tooltip: 'Search',
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded, size: 22),
              ),
            if (user.role == UserRole.student ||
                user.role == UserRole.coordinator)
              StreamBuilder<List<NotificationRecord>>(
                stream: notificationStream,
                builder: (context, snapshot) {
                  final unreadCount =
                      (snapshot.data ?? const <NotificationRecord>[])
                          .where((notice) => !notice.isReadBy(user.uid))
                          .length;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        tooltip: snapshot.hasError
                            ? 'Notification loading error (open for details)'
                            : unreadCount > 0
                            ? 'Notifications ($unreadCount unread)'
                            : 'Notifications',
                        onPressed: onNotifications,
                        icon: const Icon(
                          Icons.notifications_none_rounded,
                          size: 22,
                        ),
                      ),
                      if (snapshot.hasError || unreadCount > 0)
                        Positioned(
                          top: 3,
                          right: 1,
                          child: IgnorePointer(
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppTheme.danger,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                snapshot.hasError
                                    ? '!'
                                    : unreadCount > 99
                                    ? '99+'
                                    : '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTheme.fontCaption,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              )
            else
              IconButton(
                tooltip: 'Notifications',
                onPressed: onNotifications,
                icon: const Icon(Icons.notifications_none_rounded, size: 22),
              ),
            SizedBox(width: desktop ? 7 : 2),
            MenuAnchor(
              style: workspaceMenuStyle(
                width: 152,
                alignment: AlignmentDirectional.bottomEnd,
              ),
              alignmentOffset: const Offset(0, 6),
              menuChildren: [
                MenuItemButton(
                  style: workspaceMenuItemStyle(),
                  leadingIcon: const Icon(Icons.logout_rounded, size: 18),
                  onPressed: onLogout,
                  child: const Text('Sign out'),
                ),
              ],
              builder: (context, menu, child) => Semantics(
                expanded: menu.isOpen,
                child: Tooltip(
                  message: 'Account menu',
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                      foregroundColor: AppTheme.text,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                    child: child!,
                  ),
                ),
              ),
              child: Container(
                constraints: BoxConstraints(maxWidth: desktop ? 240 : 48),
                padding: EdgeInsets.fromLTRB(
                  desktop ? 7 : 5,
                  5,
                  desktop ? 10 : 5,
                  5,
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppTheme.sky,
                      foregroundColor: AppTheme.deepBlue,
                      child: Text(
                        _initials(user.displayName),
                        style: const TextStyle(
                          fontSize: AppTheme.fontCaption,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (desktop) ...[
                      const SizedBox(width: 9),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppTheme.fontSmall,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.text,
                              ),
                            ),
                            Text(
                              user.role.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppTheme.fontCaption,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.features,
    required this.selected,
    required this.user,
    required this.expanded,
    required this.onSelected,
  });

  static const _surface = Color(0xFF082952);

  final List<AppFeature> features;
  final AppFeature selected;
  final AppUser user;
  final bool expanded;
  final ValueChanged<AppFeature> onSelected;

  @override
  Widget build(BuildContext context) => Material(
    color: _surface,
    child: Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          right: 0,
          bottom: 0,
          width: expanded ? 190 : 72,
          height: expanded ? 45 : 25,
          child: const IgnorePointer(
            child: CustomPaint(
              painter: SsuRibbonPainter(
                bottomRight: true,
                base: Color(0xFF1458AC),
              ),
            ),
          ),
        ),
        SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 16 : 10,
                  vertical: expanded ? 19 : 20,
                ),
                child: Row(
                  mainAxisAlignment: expanded
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    SsuSeal(size: expanded ? 50 : 36),
                    if (expanded) ...[
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Practicum Connect',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'CAS Internship Management',
                              style: TextStyle(
                                color: Color(0xFFC9DAF0),
                                fontSize: 11,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF24446B)),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: expanded ? 12 : 10,
                    vertical: 10,
                  ),
                  itemCount: features.length,
                  itemBuilder: (context, index) {
                    final feature = features[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: _NavigationItem(
                        label: feature.labelForRole(user.role),
                        icon: feature.icon,
                        expanded: expanded,
                        selected: selected == feature,
                        onTap: () => onSelected(feature),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Color(0xFF24446B)),
              Padding(
                padding: EdgeInsets.fromLTRB(10, 6, 10, expanded ? 34 : 20),
                child: _NavigationItem(
                  label: 'Help & Support',
                  icon: Icons.help_outline_rounded,
                  expanded: expanded,
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationIcon: const SsuSeal(size: 42),
                    applicationName: 'Practicum Connect',
                    applicationVersion: '0.1.0',
                    applicationLegalese: 'CAS Internship Management System',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(9));
    final item = Semantics(
      label: expanded ? null : label,
      button: true,
      selected: selected,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? AppTheme.blue : Colors.transparent,
          borderRadius: radius,
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          focusColor: Colors.white.withValues(alpha: .18),
          hoverColor: Colors.white.withValues(alpha: .09),
          splashColor: Colors.white.withValues(alpha: .14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 43),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: Colors.white),
                if (expanded) ...[
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : const Color(0xFFE0EAFA),
                        fontSize: AppTheme.fontSmall,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return expanded
        ? item
        : Tooltip(message: label, excludeFromSemantics: true, child: item);
  }
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
    .join();
