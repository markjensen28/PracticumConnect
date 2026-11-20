import 'app_user.dart';
import 'records.dart';
import 'workflow_models.dart';

class RequirementCompliance {
  const RequirementCompliance(this.verified, this.assigned, this.hasYear);

  final int verified;
  final int assigned;
  final bool hasYear;

  String get label {
    if (!hasYear) return 'Academic year unavailable';
    if (assigned == 0) return 'No requirements assigned';
    return '$verified / $assigned';
  }

  factory RequirementCompliance.forStudent(
    AppUser student,
    Iterable<RequirementDefinition> definitions,
    Iterable<RequirementRecord> records,
  ) {
    final assigned = definitions
        .where((d) => d.active && d.appliesToProgram(student.program))
        .toList();
    final ids = {for (final d in assigned) d.id};
    final titles = <String, String?>{};
    for (final definition in assigned) {
      final title = definition.title.trim().toLowerCase();
      titles[title] = titles.containsKey(title) ? null : definition.id;
    }
    final year = student.academicYear?.trim();
    if (year == null || year.isEmpty) {
      return RequirementCompliance(0, ids.length, false);
    }
    final latest = <String, RequirementRecord>{};
    for (final record in records) {
      if (record.studentId != student.uid ||
          record.archived ||
          record.academicYear?.trim() != year) {
        continue;
      }
      final id = record.definitionId?.isNotEmpty == true
          ? record.definitionId
          : titles[record.title.trim().toLowerCase()];
      if (id == null || !ids.contains(id)) continue;
      final prior = latest[id];
      if (prior == null ||
          record.submittedAt.isAfter(prior.submittedAt) ||
          (record.submittedAt.isAtSameMomentAs(prior.submittedAt) &&
              (record.version > prior.version ||
                  (record.version == prior.version &&
                      record.id.compareTo(prior.id) > 0)))) {
        latest[id] = record;
      }
    }
    return RequirementCompliance(
      latest.values.where((r) => r.status == ReviewStatus.verified).length,
      ids.length,
      true,
    );
  }
}
