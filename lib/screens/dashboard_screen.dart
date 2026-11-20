import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_feature.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../services/app_controller.dart';
import '../services/practicum_repository.dart';
import 'module_screens.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppFeature _selected = AppFeature.dashboard;
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
          onSelected: (feature) {
            setState(() => _selected = feature);
            if (!desktop) Navigator.pop(context);
          },
          onLogout: widget.controller.signOut,
        );

        final content = Scaffold(
          backgroundColor: AppTheme.background,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(72),
            child: _TopBar(
              user: user,
              notificationStream: _notificationStream,
              desktop: desktop,
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
                  width: 280,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(),
                  child: navigation,
                ),
          body: LayoutBuilder(
            builder: (context, bodyConstraints) {
              final roomy = bodyConstraints.maxWidth >= 900;
              final horizontalPadding = roomy ? 24.0 : 16.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  roomy ? 24 : 16,
                  horizontalPadding,
                  roomy ? 28 : 18,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
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

        if (!desktop) return content;
        return ColoredBox(
          color: Colors.white,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 272, child: navigation),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: content),
            ],
          ),
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
    required this.onSearch,
    required this.onNotifications,
    required this.onLogout,
  });

  final AppUser user;
  final Stream<List<NotificationRecord>> notificationStream;
  final bool desktop;
  final VoidCallback onSearch;
  final VoidCallback? onNotifications;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SafeArea(
      bottom: false,
      child: Container(
        height: 72,
        padding: EdgeInsets.symmetric(horizontal: desktop ? 28 : 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            if (!desktop)
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
            if (!desktop) ...[
              const SizedBox(width: 4),
              const Expanded(child: _CompactBrand()),
            ],
            if (desktop)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SizedBox(
                  width: 390,
                  height: 46,
                  child: TextField(
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(fontSize: AppTheme.fontBody),
                    onTap: onSearch,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      hintStyle: const TextStyle(fontSize: AppTheme.fontSmall),
                      hintText: switch (user.role) {
                        UserRole.student => 'Search requirements or documents',
                        UserRole.coordinator =>
                          'Search assigned interns or documents',
                        UserRole.admin =>
                          'Search students, documents, institutions',
                      },
                      suffixIcon: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                      ),
                    ),
                  ),
                ),
              ),
            if (desktop) const Spacer(),
            if (!desktop)
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
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Account menu',
              onSelected: (value) {
                if (value == 'logout') onLogout();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Sign out'),
                    ],
                  ),
                ),
              ],
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
                      radius: 16,
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

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surfaceBlue,
          borderRadius: BorderRadius.all(Radius.circular(10)),
          border: Border.fromBorderSide(BorderSide(color: AppTheme.border)),
        ),
        child: Padding(
          padding: EdgeInsets.all(7),
          child: Icon(Icons.hub_outlined, color: AppTheme.blue, size: 18),
        ),
      ),
      SizedBox(width: 8),
      Flexible(
        child: Text(
          'Practicum Connect',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppTheme.navy,
            fontWeight: FontWeight.w800,
            fontSize: AppTheme.fontSmall,
          ),
        ),
      ),
    ],
  );
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.features,
    required this.selected,
    required this.user,
    required this.onSelected,
    required this.onLogout,
  });

  final List<AppFeature> features;
  final AppFeature selected;
  final AppUser user;
  final ValueChanged<AppFeature> onSelected;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.navy,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 16, 20),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF2C4567),
                    borderRadius: BorderRadius.all(Radius.circular(11)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.hub_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Practicum Connect',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: AppTheme.fontBody,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'CAS Internship Management',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFC1CCDC),
                          fontSize: AppTheme.fontCaption,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3B506C)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
              children: features.map((feature) {
                final active = selected == feature;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(feature),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 170),
                      curve: Curves.easeOut,
                      constraints: const BoxConstraints(minHeight: 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF2C486D)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 31,
                            height: 31,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              feature.icon,
                              size: 21,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFFC1CCDC),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              feature.labelForRole(user.role),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : const Color(0xFFDFE6F0),
                                fontSize: AppTheme.fontBody,
                                fontWeight: active
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (active)
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF3B506C)),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'Practicum Connect',
                    applicationVersion: '0.1.0',
                    applicationLegalese: 'CAS Internship Management System',
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.help_outline_rounded,
                          size: 20,
                          color: Color(0xFFC1CCDC),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Help & Support',
                          style: TextStyle(
                            fontSize: AppTheme.fontSmall,
                            color: Color(0xFFDFE6F0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .take(2)
    .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
    .join();
