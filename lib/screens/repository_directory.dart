import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/app_user.dart';
import '../models/records.dart';

class RepositoryFolder {
  RepositoryFolder(this.id, this.label);

  final String id;
  final String label;
  final children = <String, RepositoryFolder>{};
  final documents = <RequirementRecord>[];

  RepositoryFolder _child(String id, String label) =>
      children.putIfAbsent(id, () => RepositoryFolder(id, label));

  List<RepositoryFolder> resolve(List<String> path) {
    final chain = [this];
    for (final id in path) {
      final next = chain.last.children[id];
      if (next == null) break;
      chain.add(next);
    }
    return chain;
  }

  static RepositoryFolder build(
    List<AppUser> students,
    List<RequirementRecord> records,
  ) {
    final root = RepositoryFolder('', 'All documents');
    root.documents.addAll(records);
    final roster = {for (final student in students) student.uid: student};
    final byStudent = <String, List<RequirementRecord>>{};
    for (final record in records) {
      byStudent.putIfAbsent(record.studentId, () => []).add(record);
    }
    String label(List<String?> choices, String fallback) => choices
        .map((value) => value?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => fallback);
    for (final uid in {...roster.keys, ...byStudent.keys}) {
      final student = roster[uid];
      final files = byStudent[uid] ?? [];
      final latest = files.firstOrNull;
      final department = label([
        student?.department,
        student?.program,
        latest?.program,
      ], 'Unassigned department');
      final section = label([student?.section], 'Unassigned section');
      final name = label([
        student?.displayName,
        latest?.studentName,
      ], 'Unnamed student');
      final number = label([student?.studentNumber, latest?.studentNumber], '');
      final deptFolder = root._child(department.toLowerCase(), department);
      final sectionFolder = deptFolder._child(section.toLowerCase(), section);
      final studentFolder = sectionFolder._child(
        uid,
        number.isEmpty ? name : '$name · $number',
      );
      for (final folder in [deptFolder, sectionFolder, studentFolder]) {
        folder.documents.addAll(files);
      }
      for (final file in files) {
        final category = label([file.category], 'Uncategorized');
        studentFolder
            ._child(category.toLowerCase(), category)
            .documents
            .add(file);
      }
    }
    return root;
  }
}

class RepositoryDirectory extends StatefulWidget {
  const RepositoryDirectory({
    super.key,
    required this.chain,
    required this.onSelect,
  });
  final List<RepositoryFolder> chain;
  final ValueChanged<List<String>> onSelect;

  @override
  State<RepositoryDirectory> createState() => _RepositoryDirectoryState();
}

class _RepositoryDirectoryState extends State<RepositoryDirectory> {
  String _search = '';
  static const colors = [
    Color(0xffbc8421),
    Color(0xff278879),
    Color(0xff497acd),
    Color(0xff865da8),
  ];

  @override
  Widget build(BuildContext context) {
    final visible = <({RepositoryFolder folder, List<String> path})>[];
    final chain = widget.chain;
    void add(RepositoryFolder folder, List<String> path) {
      final matches =
          _search.isEmpty || folder.label.toLowerCase().contains(_search);
      if (matches) visible.add((folder: folder, path: path));
      if (_search.isEmpty &&
          (path.length >= chain.length || chain[path.length] != folder)) {
        return;
      }
      final children = folder.children.values.toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
      for (final child in children) {
        add(child, [...path, child.id]);
      }
    }

    add(chain.first, []);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.folder_copy_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'File directory',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search folders',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
            ),
          ),
          const Divider(height: 1),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No matching folders'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final row = visible[i];
                final depth = row.path.length;
                final selected = row.folder == chain.last;
                final color = depth == 0 ? AppTheme.blue : colors[depth - 1];
                return Material(
                  color: selected ? AppTheme.surfaceBlue : Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onSelect(row.path),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(10 + depth * 8, 9, 10, 9),
                      child: Row(
                        children: [
                          Icon(
                            chain.contains(row.folder)
                                ? Icons.folder_open_rounded
                                : Icons.folder_rounded,
                            color: color,
                            size: 20,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _search.isEmpty || depth == 0
                                  ? row.folder.label
                                  : chain.first
                                        .resolve(row.path)
                                        .skip(1)
                                        .map((f) => f.label)
                                        .join(' / '),
                              style: TextStyle(
                                fontSize: AppTheme.fontSmall,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${row.folder.documents.length}',
                            style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: AppTheme.fontCaption,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
