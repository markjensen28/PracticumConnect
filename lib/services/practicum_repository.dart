import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import '../models/app_user.dart';
import '../models/records.dart';
import '../models/workflow_models.dart';
import '../models/pdf_form_template.dart';

import 'notification_schedule.dart';

class PracticumRepository {
  PracticumRepository({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  // Students receive submission status only, never confidential evaluation data.
  Stream<bool> watchStudentEvaluationSubmitted(String studentId) => _db
      .collection('evaluation_status')
      .doc(studentId)
      .snapshots()
      .map((snapshot) => snapshot.data()?['status'] == 'submitted');
  // Reads only student-visible status documents, never supervisor evaluations.
  // Filter by academic year so older evaluations do not appear as current ones.
  Stream<List<String>> watchStudentEvaluationStatuses(
    String studentId,
    String? academicYear,
  ) {
    if (academicYear == null || academicYear.trim().isEmpty) {
      return Stream.value(const <String>[]);
    }

    return _db
        .collection('evaluation_status')
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => doc.data()['academicYear'] == academicYear)
              .map((doc) => doc.data()['status'])
              .where((status) => status == 'pending' || status == 'submitted')
              .cast<String>()
              .toList(),
        );
  }

  Stream<List<RequirementRecord>> watchRequirements(AppUser user) =>
      watchRepositoryDocuments(
        user,
      ).map((records) => records.where((r) => !r.archived).toList());

  Stream<List<RequirementRecord>> watchRepositoryDocuments(AppUser user) {
    Query<Map<String, dynamic>> query = _db.collection('requirements');
    if (user.role == UserRole.student) {
      query = query.where('studentId', isEqualTo: user.uid);
    } else if (user.role == UserRole.coordinator) {
      query = query.where('coordinatorId', isEqualTo: user.uid);
    }
    return query.snapshots().map((snapshot) {
      final records = snapshot.docs.map(RequirementRecord.fromDoc).toList();
      records.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return records;
    });
  }

  Stream<List<DtrRecord>> watchDtr(AppUser user) {
    Query<Map<String, dynamic>> query = _db.collection('dtr_entries');
    if (user.role == UserRole.student) {
      query = query.where('studentId', isEqualTo: user.uid);
    } else if (user.role == UserRole.coordinator) {
      query = query.where('coordinatorId', isEqualTo: user.uid);
    }
    return query.snapshots().map((snapshot) {
      final records = snapshot.docs
          .map(DtrRecord.fromDoc)
          .where((record) => !record.archived)
          .toList();
      records.sort((a, b) => b.date.compareTo(a.date));
      return records;
    });
  }

  Stream<int> watchReminderHours(AppUser user) =>
      _db.collection('users').doc(user.uid).snapshots().map((snapshot) {
        final hours = snapshot.data()?['reminderHours'];
        if (hours is int && hours >= 1 && hours <= 720) return hours;
        return user.role == UserRole.student ? 72 : 48;
      });

  Future<void> saveReminderHours(AppUser user, int hours) async {
    if (hours < 1 || hours > 720) {
      throw ArgumentError('Choose between 1 hour and 30 days.');
    }
    await _db.collection('users').doc(user.uid).update({
      'reminderHours': hours,
    });
  }

  Stream<List<NotificationRecord>> watchNotificationManagement(AppUser user) {
    if (user.role != UserRole.admin) {
      throw StateError('Administrator access required.');
    }
    return watchNotificationSchedule(
      _db.collection('notifications').snapshots().map((snapshot) {
        final records = snapshot.docs.map(NotificationRecord.fromDoc).toList();
        records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return records;
      }),
      includeFuture: true,
    );
  }

  Stream<List<NotificationRecord>> watchNotifications(AppUser user) {
    final allQuery = _db
        .collection('notifications')
        .where('active', isEqualTo: true)
        .where('targetRole', isEqualTo: 'all')
        .where('targetUserId', isNull: true);

    final roleQuery = _db
        .collection('notifications')
        .where('active', isEqualTo: true)
        .where('targetRole', isEqualTo: user.role.value)
        .where('targetUserId', isNull: true);

    final targetedQuery = _db
        .collection('notifications')
        .where('active', isEqualTo: true)
        .where('targetRole', isEqualTo: 'user:${user.uid}')
        .where('targetUserId', isEqualTo: user.uid);

    late final StreamController<List<NotificationRecord>> controller;

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? allSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? roleSubscription;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
    targetedSubscription;

    var allRecords = <String, NotificationRecord>{};
    var roleRecords = <String, NotificationRecord>{};
    var targetedRecords = <String, NotificationRecord>{};

    void emitRecords() {
      final merged = <String, NotificationRecord>{
        ...allRecords,
        ...roleRecords,
        ...targetedRecords,
      };

      final records =
          merged.values
              .where(
                (record) => record.active && !record.isDismissedBy(user.uid),
              )
              .toList()
            ..sort((a, b) => b.deliveryTime.compareTo(a.deliveryTime));

      controller.add(records);
    }

    controller = StreamController<List<NotificationRecord>>(
      onListen: () {
        allSubscription = allQuery.snapshots().listen((snapshot) {
          allRecords = {
            for (final doc in snapshot.docs)
              doc.id: NotificationRecord.fromDoc(doc),
          };
          emitRecords();
        }, onError: controller.addError);

        roleSubscription = roleQuery.snapshots().listen((snapshot) {
          roleRecords = {
            for (final doc in snapshot.docs)
              doc.id: NotificationRecord.fromDoc(doc),
          };
          emitRecords();
        }, onError: controller.addError);

        targetedSubscription = targetedQuery.snapshots().listen((snapshot) {
          targetedRecords = {
            for (final doc in snapshot.docs)
              doc.id: NotificationRecord.fromDoc(doc),
          };
          emitRecords();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await allSubscription?.cancel();
        await roleSubscription?.cancel();
        await targetedSubscription?.cancel();
      },
    );

    return watchNotificationSchedule(controller.stream);
  }

  Stream<List<AppUser>> watchUsers({UserRole? role}) {
    Query<Map<String, dynamic>> query = _db.collection('users');
    if (role != null) {
      query = query.where('role', isEqualTo: role.value);
    }
    return query.snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .toList();
      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return users;
    });
  }

  Future<AppUser?> getStudentById(String studentId) async {
    if (studentId.trim().isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('users').doc(studentId).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    final student = AppUser.fromMap(snapshot.id, data);
    return student.role == UserRole.student ? student : null;
  }

  Future<Map<String, dynamic>> importStudentRoster(
    List<dynamic> rows, {
    required bool preview,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final uri = Uri.parse(
      AppConfig.coordinatorApprovalApiUrl,
    ).resolve('/api/student-roster');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': preview ? 'preview' : 'import',
        'rows': rows,
      }),
    );
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(
        result['error'] as String? ?? 'Could not import roster.',
      );
    }
    return result;
  }

  Stream<List<AppUser>> watchStudentsFor(AppUser actor) =>
      _watchStudents(actor);

  Stream<List<AppUser>> watchStudentDirectory(AppUser actor) =>
      _watchStudents(actor, includePending: actor.role == UserRole.admin);

  Stream<List<AppUser>> _watchStudents(
    AppUser actor, {
    bool includePending = false,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('users')
        .where('role', isEqualTo: UserRole.student.value);
    if (actor.role == UserRole.coordinator) {
      query = query.where('coordinatorId', isEqualTo: actor.uid);
    } else if (actor.role == UserRole.student) {
      query = query.where(FieldPath.documentId, isEqualTo: actor.uid);
    }
    return query.snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) => AppUser.fromMap(doc.id, doc.data()))
          .where(
            (student) =>
                student.active ||
                (includePending && student.enrollmentStatus == 'pending'),
          )
          .toList();
      users.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return users;
    });
  }

  Stream<List<PartnerInstitutionRecord>> watchPartnerInstitutions() =>
      _db.collection('partner_institutions').snapshots().map((snapshot) {
        final records = snapshot.docs
            .map(PartnerInstitutionRecord.fromDoc)
            .toList();
        records.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return records;
      });

  Future<String> savePartnerInstitution({
    required AppUser actor,
    String? id,
    required String name,
    required String address,
    required String institutionType,
    required String industryField,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required List<String> programs,
    required String status,
    required String remarks,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can manage partner institutions.',
      );
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Partner institution name is required.');
    }
    if (contactEmail.trim().isNotEmpty && !contactEmail.contains('@')) {
      throw ArgumentError('Enter a valid partner contact email.');
    }
    final reference = id == null
        ? _db.collection('partner_institutions').doc()
        : _db.collection('partner_institutions').doc(id);
    await reference.set({
      'name': name.trim(),
      'address': address.trim(),
      'institutionType': institutionType.trim(),
      'industryField': industryField.trim(),
      'contactName': contactName.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'programs': programs,
      'status': status.trim().isEmpty ? 'Active' : status.trim(),
      'remarks': remarks.trim(),
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(
      actor,
      '${id == null ? 'Added' : 'Updated'} partner institution: ${name.trim()}',
    );
    return reference.id;
  }

  Future<void> deletePartnerInstitution({
    required AppUser actor,
    required PartnerInstitutionRecord partner,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can remove partner institutions.',
      );
    }
    final linked = await _db
        .collection('moas')
        .where('partnerId', isEqualTo: partner.id)
        .limit(1)
        .get();
    if (linked.docs.isNotEmpty) {
      throw StateError(
        'This partner has linked MOA records. Keep the partner record or update the MOA records first.',
      );
    }
    await _db.collection('partner_institutions').doc(partner.id).delete();
    await _log(actor, 'Deleted partner institution: ${partner.name}');
  }

  Stream<List<MoaRecord>> watchMoas() =>
      _db.collection('moas').snapshots().map((snapshot) {
        final records = snapshot.docs.map(MoaRecord.fromDoc).toList();
        records.sort((a, b) => b.endDate.compareTo(a.endDate));
        return records;
      });

  Stream<List<RequirementDefinition>> watchRequirementDefinitions() =>
      _db.collection('requirement_definitions').snapshots().map((snapshot) {
        final definitions = snapshot.docs
            .map(RequirementDefinition.fromDoc)
            .where((definition) => definition.active)
            .toList();
        definitions.sort((a, b) {
          final order = a.sortOrder.compareTo(b.sortOrder);
          return order == 0 ? a.dueDate.compareTo(b.dueDate) : order;
        });
        return definitions;
      });

  Stream<InternshipProfileRecord?> watchInternshipProfile(String studentId) =>
      _db
          .collection('internship_profiles')
          .doc(studentId)
          .snapshots()
          .map(
            (snapshot) => snapshot.exists
                ? InternshipProfileRecord.fromDoc(snapshot)
                : null,
          );

  Stream<List<InternshipProfileRecord>> watchInternshipProfilesFor(
    AppUser actor,
  ) {
    Query<Map<String, dynamic>> query = _db.collection('internship_profiles');
    if (actor.role == UserRole.coordinator) {
      query = query.where('coordinatorId', isEqualTo: actor.uid);
    } else if (actor.role == UserRole.student) {
      query = query.where(FieldPath.documentId, isEqualTo: actor.uid);
    }
    return query.snapshots().map(
      (snapshot) => snapshot.docs
          .map(InternshipProfileRecord.fromDoc)
          .where((profile) => !profile.archived)
          .toList(),
    );
  }

  Stream<List<RequirementVersionRecord>> watchRequirementVersions(
    String requirementId,
  ) => _db
      .collection('requirement_versions')
      .where('requirementId', isEqualTo: requirementId)
      .snapshots()
      .map((snapshot) {
        final versions = snapshot.docs
            .map(RequirementVersionRecord.fromDoc)
            .toList();
        versions.sort((a, b) => b.version.compareTo(a.version));
        return versions;
      });

  Stream<List<ActivityLogRecord>> watchActivityLogs({AppUser? actor}) {
    Query<Map<String, dynamic>> query = _db.collection('activity_logs');
    if (actor?.role == UserRole.coordinator) {
      query = query.where('userId', isEqualTo: actor!.uid);
    }
    return query.limit(200).snapshots().map((snapshot) {
      final records = snapshot.docs.map(ActivityLogRecord.fromDoc).toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    });
  }

  Stream<List<SupervisorEvaluationRecord>> watchEvaluationsFor(AppUser actor) {
    if (actor.role != UserRole.admin && actor.role != UserRole.coordinator) {
      return Stream<List<SupervisorEvaluationRecord>>.error(
        StateError(
          'Confidential evaluations are available only to authorized staff.',
        ),
      );
    }

    Query<Map<String, dynamic>> query = _db.collection(
      'supervisor_evaluations',
    );
    if (actor.role == UserRole.coordinator) {
      query = query.where('coordinatorId', isEqualTo: actor.uid);
    } else if (actor.role == UserRole.student) {
      query = query.where('studentId', isEqualTo: actor.uid);
    }
    return query.snapshots().map((snapshot) {
      final records = snapshot.docs
          .map(SupervisorEvaluationRecord.fromDoc)
          .where((record) => !record.archived)
          .toList();
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    });
  }

  Stream<List<SupervisorEvaluationRecord>> watchEvaluations() =>
      _db.collection('supervisor_evaluations').snapshots().map((snapshot) {
        final records = snapshot.docs
            .map(SupervisorEvaluationRecord.fromDoc)
            .where((record) => !record.archived)
            .toList();
        records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return records;
      });

  Future<PublicEvaluationAccessRecord> loadPublicEvaluation(
    String token,
  ) async {
    final uri = Uri.parse(
      AppConfig.evaluationApiUrl,
    ).replace(queryParameters: {'token': token});
    final response = await http.get(
      uri,
      headers: const {'Accept': 'application/json'},
    );
    final payload = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Unable to load this evaluation link.',
      );
    }
    return PublicEvaluationAccessRecord.fromJson(payload);
  }

  Future<Map<String, dynamic>> _evaluationAction(
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.evaluationApiUrl),
      headers: {
        'Content-Type': 'application/json',
        if (bearer != null) 'Authorization': 'Bearer $bearer',
      },
      body: jsonEncode(body),
    );
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(
        data['error'] as String? ?? 'Evaluation request failed.',
      );
    }
    return data;
  }

  Future<void> sendEvaluationInvitation(String token) async {
    final bearer = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (bearer == null) throw StateError('Sign in to send invitations.');
    await _evaluationAction({
      'action': 'invite',
      'token': token,
    }, bearer: bearer);
  }

  Future<void> requestEvaluationCode(String token, String email) async {
    await _evaluationAction({
      'action': 'requestCode',
      'token': token,
      'email': email,
    });
  }

  Future<({String proof, PublicEvaluationAccessRecord evaluation})>
  verifyPublicEvaluationAccess({
    required String token,
    required String supervisorEmail,
    required String code,
  }) async {
    final data = await _evaluationAction({
      'action': 'verify',
      'token': token,
      'email': supervisorEmail,
      'code': code,
    });
    return (
      proof: data['proof'] as String,
      evaluation: PublicEvaluationAccessRecord.fromJson(data),
    );
  }

  Stream<SupervisorEvaluationRecord?> watchPublicEvaluation(String token) => _db
      .collection('supervisor_evaluations')
      .doc(token)
      .snapshots()
      .map(
        (snapshot) => snapshot.exists
            ? SupervisorEvaluationRecord.fromDoc(snapshot)
            : null,
      );

  Stream<List<AcademicArchiveRecord>> watchAcademicArchives() =>
      _db.collection('academic_archives').snapshots().map((snapshot) {
        final records = snapshot.docs
            .map(AcademicArchiveRecord.fromDoc)
            .toList();
        records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return records;
      });

  Future<AcademicArchiveContents> loadAcademicArchive(
    String academicYear, {
    required AppUser actor,
  }) async {
    if (!actor.role.isStaff) {
      throw StateError(
        'Archived records are available only to authorized internship staff.',
      );
    }

    Query<Map<String, dynamic>> requirementQuery = _db.collection(
      'requirements',
    );
    Query<Map<String, dynamic>> dtrQuery = _db.collection('dtr_entries');
    Query<Map<String, dynamic>> evaluationQuery = _db.collection(
      'supervisor_evaluations',
    );

    // Program Coordinators may retrieve only records belonging to interns who
    // were assigned to them. CAS College Coordinator / SIP Admin can retrieve
    // college-wide archived records.
    if (actor.role == UserRole.coordinator) {
      requirementQuery = requirementQuery.where(
        'coordinatorId',
        isEqualTo: actor.uid,
      );
      dtrQuery = dtrQuery.where('coordinatorId', isEqualTo: actor.uid);
      evaluationQuery = evaluationQuery.where(
        'coordinatorId',
        isEqualTo: actor.uid,
      );
    }

    final snapshots = await Future.wait([
      requirementQuery.get(),
      dtrQuery.get(),
      evaluationQuery.get(),
    ]);

    final requirements = snapshots[0].docs
        .map(RequirementRecord.fromDoc)
        .where(
          (record) => record.archived && record.academicYear == academicYear,
        )
        .toList();
    final dtr = snapshots[1].docs
        .map(DtrRecord.fromDoc)
        .where(
          (record) => record.archived && record.academicYear == academicYear,
        )
        .toList();
    final evaluations = snapshots[2].docs
        .map(SupervisorEvaluationRecord.fromDoc)
        .where(
          (record) => record.archived && record.academicYear == academicYear,
        )
        .toList();

    return AcademicArchiveContents(
      requirements: requirements,
      dtr: dtr,
      evaluations: evaluations,
    );
  }

  Future<String> _finalizeRequirement(Map<String, dynamic> data) async {
    final bearer = await FirebaseAuth.instance.currentUser?.getIdToken();
    final url = Uri.parse(
      AppConfig.coordinatorApprovalApiUrl,
    ).resolve('/api/requirement-submit');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $bearer',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );
    final result = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError(result['error'] ?? 'Submission failed.');
    }
    return result['id'] as String;
  }

  Future<void> submitRequirement({
    required AppUser user,
    required String title,
    required PlatformFile file,
    required RequirementDefinition definition,
  }) async {
    if (user.role != UserRole.student) {
      throw StateError('Only student interns submit requirement documents.');
    }
    if (user.academicYear?.trim().isEmpty ?? true) {
      throw StateError(
        'Your academic year is not set. Ask your coordinator to update your internship profile before submitting requirements.',
      );
    }
    if (!AppConfig.hasSupabaseConfig) {
      throw StateError(AppConfig.missingSupabaseMessage);
    }
    final storagePath = await _uploadFile(
      ownerId: user.uid,
      folder: 'requirements',
      file: file,
    );

    final id = await _finalizeRequirement({
      'definitionId': definition.id,
      'storagePath': storagePath,
      'fileName': file.name,
    });
    _scheduleRequirementFollowUps(
      user: user,
      activity: 'Submitted requirement: $title',
      notificationTitle: 'New document submitted',
      notificationMessage: '${user.displayName} submitted $title for review.',
      relatedId: id,
    );
  }

  Future<void> updateRequirementStatus({
    required String requirementId,
    required ReviewStatus status,
    required String remarks,
    required AppUser reviewer,
  }) async {
    if (!reviewer.role.isStaff) {
      throw StateError('Student interns cannot review requirements.');
    }
    final requirement = await _db
        .collection('requirements')
        .doc(requirementId)
        .get();
    final data = requirement.data();
    if (data == null) {
      throw StateError('The submitted requirement no longer exists.');
    }
    if (data['archived'] == true) {
      throw StateError('Archived submissions are read-only.');
    }
    final studentId = data['studentId'] as String? ?? '';
    await _assertCanManageStudent(reviewer, studentId);

    if (data['status'] == status.value &&
        (data['remarks'] ?? '') == remarks.trim() &&
        data['reviewedBy'] == reviewer.uid) {
      await _syncInternshipStage(studentId, actor: reviewer);
      return;
    }
    final batch = _db.batch();
    batch.update(requirement.reference, {
      'status': status.value,
      'remarks': remarks.trim(),
      'reviewedBy': reviewer.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    _queueTargetedNotification(
      batch: batch,
      actor: reviewer,
      targetUserId: studentId,
      targetRole: UserRole.student.value,
      title: status == ReviewStatus.verified
          ? '${data['title']} has been verified'
          : status == ReviewStatus.rejected
          ? '${data['title']} was rejected'
          : status == ReviewStatus.underReview
          ? '${data['title']} is under review'
          : '${data['title']} needs revision',
      message: remarks.trim().isEmpty
          ? 'Your Program Coordinator updated this document to ${status.label}.'
          : remarks.trim(),
      type: 'document_feedback',
      relatedId: requirementId,
    );

    await _syncInternshipStage(
      studentId,
      actor: reviewer,
      batch: batch,
      reviewCollection: 'requirements',
      reviewId: requirementId,
      reviewStatus: status,
    );
    _queueLog(
      batch,
      reviewer,
      'Changed requirement $requirementId to ${status.label}',
    );
    await batch.commit();
  }

  Future<void> resubmitRequirement({
    required AppUser user,
    required RequirementRecord requirement,
    required PlatformFile file,
    String? definitionId,
  }) async {
    if (user.role != UserRole.student || requirement.studentId != user.uid) {
      throw StateError('You cannot replace this requirement.');
    }
    final currentAcademicYear = user.academicYear?.trim() ?? '';
    if (currentAcademicYear.isEmpty) {
      throw StateError(
        'Your academic year is not set. Ask your coordinator to update your internship profile before resubmitting requirements.',
      );
    }
    if (requirement.academicYear?.trim() != currentAcademicYear) {
      throw StateError(
        'This requirement belongs to another academic year or has no academic year. Ask your coordinator to review it.',
      );
    }
    if (requirement.status != ReviewStatus.needsRevision &&
        requirement.status != ReviewStatus.rejected) {
      throw StateError(
        'Only requirements needing correction can be resubmitted.',
      );
    }
    final storagePath = await _uploadFile(
      ownerId: user.uid,
      folder: 'requirements',
      file: file,
    );
    await _finalizeRequirement({
      'requirementId': requirement.id,
      'expectedVersion': requirement.version,
      'definitionId': definitionId ?? requirement.definitionId,
      'storagePath': storagePath,
      'fileName': file.name,
    });
    _scheduleRequirementFollowUps(
      user: user,
      activity: 'Resubmitted requirement: ${requirement.title}',
      notificationTitle: 'Corrected document resubmitted',
      notificationMessage:
          '${user.displayName} resubmitted ${requirement.title}.',
      relatedId: requirement.id,
    );
  }

  Future<String> createDownloadUrl(String path) async {
    var normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Storage path is required.');
    }

    final parsed = Uri.tryParse(normalizedPath);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      return normalizedPath;
    }

    if (!AppConfig.hasSupabaseConfig) {
      throw StateError(AppConfig.missingSupabaseMessage);
    }

    // Older records may contain a leading slash or the bucket name as part of
    // storagePath. Supabase createSignedUrl expects only the object path.
    normalizedPath = normalizedPath.replaceFirst(RegExp(r'^/+'), '');
    final bucketPrefix = '${AppConfig.supabaseBucket}/';
    if (normalizedPath.startsWith(bucketPrefix)) {
      normalizedPath = normalizedPath.substring(bucketPrefix.length);
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in again before opening a stored document.');
    }

    final ownerId = normalizedPath.split('/').first;
    final isSharedTemplate =
        normalizedPath.split('/').length == 3 &&
        normalizedPath.split('/')[1] == 'form_templates';
    if (ownerId != firebaseUser.uid && !isSharedTemplate) {
      final token = await firebaseUser.getIdToken();
      final response = await http.post(
        Uri.parse(AppConfig.documentDownloadApiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'path': normalizedPath}),
      );
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200 || payload['url'] is! String) {
        throw StateError(
          payload['error'] as String? ?? 'Document access denied.',
        );
      }
      return payload['url'] as String;
    }
    await firebaseUser.getIdTokenResult(true);

    try {
      return await Supabase.instance.client.storage
          .from(AppConfig.supabaseBucket)
          .createSignedUrl(normalizedPath, 300);
    } on StorageException catch (error) {
      if (error.statusCode == '403' &&
          error.message.contains('Header Parameter value not allowed')) {
        throw StateError(
          'Supabase rejected the Firebase ID token before it could check the '
          'file. In the Supabase project configured for this app, enable '
          'Authentication > Third-Party Auth > Firebase and set the Firebase '
          'project ID to practicumconnect-aa5d1. Firebase users also '
          'need the role=authenticated custom claim. After updating these '
          'settings, sign out and back in, then try opening the file again.',
        );
      }
      if (error.statusCode == '500' &&
          error.message.toLowerCase().contains('database')) {
        throw StateError(
          'Supabase rejected the Firebase database role for this session. '
          'Practicum Connect requires Firebase claim role=authenticated and '
          'uses app_role for admin/coordinator authorization. Sign out and back '
          'in, then retry. If needed, keep the local staff-claims API running so '
          'the app can repair the token automatically.',
        );
      }
      if (error.statusCode == '404' ||
          error.statusCode == '400' ||
          error.message.toLowerCase().contains('not found')) {
        throw StateError(
          'The stored file could not be found or is not readable at "$normalizedPath". '
          'For a student requirement, verify the coordinator app_role claim and '
          'the Supabase Storage policies; if the object was deleted, the student '
          'must resubmit it. For an MOA, use Replace File / Renew to upload a new '
          'copy and repair the saved storage path.',
        );
      }
      rethrow;
    }
  }

  Future<RequirementRecord?> getRequirement(String id) async {
    if (id.isEmpty) {
      return null;
    }
    final snapshot = await _db.collection('requirements').doc(id).get();
    return snapshot.exists ? RequirementRecord.fromDoc(snapshot) : null;
  }

  Future<void> syncInternshipStatus({
    required AppUser actor,
    required String studentId,
  }) async {
    if (!actor.role.isStaff) {
      throw StateError('Only authorized internship staff can sync status.');
    }
    await _assertCanManageStudent(actor, studentId);
    await _syncInternshipStage(studentId, actor: actor);

    Query<Map<String, dynamic>> evaluationQuery = _db
        .collection('supervisor_evaluations')
        .where('studentId', isEqualTo: studentId);

    if (actor.role == UserRole.coordinator) {
      evaluationQuery = evaluationQuery.where(
        'coordinatorId',
        isEqualTo: actor.uid,
      );
    }

    final evaluations = await evaluationQuery.get();
    final pending = evaluations.docs
        .where(
          (doc) =>
              doc.data()['archived'] != true &&
              doc.data()['statusSyncPending'] == true,
        )
        .toList();
    for (var offset = 0; offset < pending.length; offset += 450) {
      final batch = _db.batch();
      final docs = pending;
      final endIndex = min(offset + 450, docs.length);
      for (final doc in docs.sublist(offset, endIndex)) {
        batch.update(doc.reference, {
          'statusSyncPending': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
  }

  Future<void> updateDtrStatus({
    required AppUser reviewer,
    required String recordId,
    required ReviewStatus status,
    required String remarks,
  }) async {
    if (!reviewer.role.isStaff) {
      throw StateError('Student interns cannot review DTR entries.');
    }
    final reference = _db.collection('dtr_entries').doc(recordId);
    final snapshot = await reference.get();
    final data = snapshot.data();
    if (data == null) {
      throw StateError('The selected DTR entry no longer exists.');
    }
    if (data['archived'] == true) {
      throw StateError('Archived attendance is read-only.');
    }
    final studentId = data['studentId'] as String? ?? '';
    await _assertCanManageStudent(reviewer, studentId);

    if (data['status'] == status.value &&
        (data['remarks'] ?? '') == remarks.trim() &&
        data['reviewedBy'] == reviewer.uid) {
      await _syncInternshipStage(studentId, actor: reviewer);
      return;
    }
    final batch = _db.batch();
    batch.update(reference, {
      'status': status.value,
      'remarks': remarks.trim(),
      'reviewedBy': reviewer.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _queueTargetedNotification(
      batch: batch,
      actor: reviewer,
      targetUserId: studentId,
      targetRole: UserRole.student.value,
      title: status == ReviewStatus.verified
          ? 'DTR entry approved'
          : status == ReviewStatus.needsRevision ||
                status == ReviewStatus.rejected
          ? 'DTR entry requires correction'
          : 'DTR review updated',
      message: remarks.trim().isEmpty
          ? 'Your DTR status is now ${status.label}.'
          : remarks.trim(),
      type: 'dtr_update',
      relatedId: recordId,
    );
    await _syncInternshipStage(
      studentId,
      actor: reviewer,
      batch: batch,
      reviewCollection: 'dtr_entries',
      reviewId: recordId,
      reviewStatus: status,
    );
    _queueLog(batch, reviewer, 'Changed DTR $recordId to ${status.label}');
    await batch.commit();
  }

  Future<void> sendNotification({
    required AppUser actor,
    required String title,
    required String message,
    required String targetRole,
    String? targetUserId,
    String type = 'general',
    String? relatedId,
    String priority = 'normal',
    DateTime? scheduledFor,
    String? linkUrl,
  }) async {
    if (title.trim().isEmpty || message.trim().isEmpty) {
      throw ArgumentError('Notification title and message are required.');
    }

    if (actor.role == UserRole.student) {
      if (targetUserId == null ||
          targetUserId != actor.coordinatorId ||
          targetRole != UserRole.coordinator.value) {
        throw StateError(
          'Student interns may only send workflow updates to their assigned Program Coordinator.',
        );
      }
    } else if (actor.role == UserRole.coordinator) {
      if (targetUserId == null || targetRole != UserRole.student.value) {
        throw StateError(
          'Program Coordinators may only send targeted workflow notifications to assigned interns.',
        );
      }
      await _assertCanManageStudent(actor, targetUserId);
    }

    await _db.collection('notifications').add({
      'title': title.trim(),
      'message': message.trim(),
      'targetRole': targetUserId == null ? targetRole : 'user:$targetUserId',
      'targetUserId': targetUserId,
      'type': type,
      'relatedId': relatedId,
      'priority': priority,
      'scheduledFor': scheduledFor == null
          ? null
          : Timestamp.fromDate(scheduledFor),
      'linkUrl': linkUrl?.trim().isEmpty == true ? null : linkUrl?.trim(),
      'readBy': <String>[],
      'createdBy': actor.uid,
      'read': false,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(actor, 'Published notification: ${title.trim()}');
  }

  Future<void> markNotificationRead({
    required AppUser user,
    required NotificationRecord notification,
  }) async {
    if (notification.isReadBy(user.uid)) {
      return;
    }
    await _db.collection('notifications').doc(notification.id).update({
      'readBy': FieldValue.arrayUnion([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> dismissNotificationForUser({
    required AppUser user,
    required NotificationRecord notification,
  }) async {
    if (user.role == UserRole.admin) {
      throw StateError(
        'Use the administrative notification controls for admin deletion.',
      );
    }

    if (notification.isDismissedBy(user.uid)) {
      return;
    }

    await _db.collection('notifications').doc(notification.id).update({
      'dismissedBy': FieldValue.arrayUnion([user.uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveInternshipProfile({
    required AppUser actor,
    required AppUser student,
    required String program,
    String? academicDepartment,
    String? section,
    required String yearLevel,
    required String academicYear,
    required InternshipProfileRecord profile,
  }) async {
    if (!actor.role.isStaff) {
      throw StateError(
        'Student interns cannot update internship placement records.',
      );
    }
    await _assertCanManageStudent(actor, student.uid);
    if (profile.requiredHours <= 0) {
      throw ArgumentError('Required hours must be greater than zero.');
    }
    if ((profile.shiftStartMinutes == null) !=
        (profile.shiftEndMinutes == null)) {
      throw ArgumentError('Set both shift start and shift end times.');
    }
    if (profile.shiftStartMinutes != null &&
        (profile.shiftStartMinutes! < 0 ||
            profile.shiftEndMinutes! > 1439 ||
            profile.shiftStartMinutes! >= profile.shiftEndMinutes!)) {
      throw ArgumentError(
        'Shift end must be later than shift start on the same day.',
      );
    }
    if (profile.workDays.isEmpty) {
      throw ArgumentError('Select at least one scheduled work day.');
    }

    final coordinatorId =
        student.coordinatorId ??
        (actor.role == UserRole.coordinator
            ? actor.uid
            : profile.coordinatorId);

    final batch = _db.batch();
    final profileChanges = <String, dynamic>{
      'status': profile.status,
      'placementStatus': profile.placementStatus,
      'companyName': profile.companyName.trim(),
      'department': profile.department.trim(),
      'position': profile.position.trim(),
      'startDate': profile.startDate == null
          ? null
          : Timestamp.fromDate(profile.startDate!),
      'endDate': profile.endDate == null
          ? null
          : Timestamp.fromDate(profile.endDate!),
      'shiftStartMinutes': profile.shiftStartMinutes,
      'shiftEndMinutes': profile.shiftEndMinutes,
      'workDays': profile.workDays,
      'timeZone': profile.timeZone,
      'requiredHours': profile.requiredHours,
      'supervisorName': profile.supervisorName.trim(),
      'supervisorEmail': profile.supervisorEmail.trim(),
      'supervisorPhone': profile.supervisorPhone.trim(),
      'coordinatorRemarks': profile.coordinatorRemarks.trim(),
      'coordinatorId': coordinatorId,
      'academicYear': academicYear.trim(),
      'archived': profile.archived,
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final userChanges = <String, dynamic>{
      'program': program.trim(),
      if (academicDepartment != null) 'department': academicDepartment.trim(),
      if (section != null) 'section': section.trim(),
      'yearLevel': yearLevel.trim(),
      'academicYear': academicYear.trim(),
      if (actor.role == UserRole.admin) 'coordinatorId': coordinatorId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Retrying an already committed save must not publish another audit event.
    final savedProfile = await _db
        .collection('internship_profiles')
        .doc(student.uid)
        .get();
    if (savedProfile.data()?['archived'] == true) {
      throw StateError('Archived internship profiles are read-only.');
    }
    final savedUser = await _db.collection('users').doc(student.uid).get();
    bool matches(Map<String, dynamic> changes, Map<String, dynamic>? saved) =>
        saved != null &&
        changes.entries.every((entry) {
          if (['status', 'updatedAt', 'updatedBy'].contains(entry.key)) {
            return true;
          }
          final value = saved[entry.key];
          return entry.value is List && value is List
              ? listEquals(entry.value as List, value)
              : entry.value == value;
        });
    if (matches(profileChanges, savedProfile.data()) &&
        matches(userChanges, savedUser.data())) {
      await _syncInternshipStage(student.uid, actor: actor);
      return;
    }

    batch.set(
      _db.collection('internship_profiles').doc(student.uid),
      profileChanges,
      SetOptions(merge: true),
    );
    batch.update(_db.collection('users').doc(student.uid), userChanges);
    await _syncInternshipStage(
      student.uid,
      actor: actor,
      batch: batch,
      profileChanges: profileChanges,
      userChanges: userChanges,
    );
    _queueLog(
      batch,
      actor,
      'Updated internship profile for ${student.displayName}',
    );
    await batch.commit();
  }

  Future<void> clockIn({
    required AppUser student,
    required Uint8List photoBytes,
  }) async {
    if (student.role != UserRole.student || student.uid.isEmpty) {
      throw StateError('Only a signed-in student can clock in.');
    }
    if (photoBytes.isEmpty || photoBytes.length > 5 * 1024 * 1024) {
      throw StateError('The check-in photo must be smaller than 5 MB.');
    }
    final path = await _uploadBytes(
      ownerId: student.uid,
      folder: 'dtr-checkins',
      fileName: 'check-in.jpg',
      bytes: photoBytes,
      contentType: 'image/jpeg',
    );
    await _dtrAttendanceRequest({
      'action': 'clock_in',
      'photoPath': path,
      'studentName': student.displayName,
    });
  }

  Future<void> clockOut({required AppUser student}) async {
    if (student.role != UserRole.student || student.uid.isEmpty) {
      throw StateError('Only a signed-in student can clock out.');
    }
    await _dtrAttendanceRequest({'action': 'clock_out'});
  }

  Future<String?> signedDtrPhotoUrl(String path) async {
    if (!AppConfig.hasSupabaseConfig || path.trim().isEmpty) return null;
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;
    await firebaseUser.getIdTokenResult(true);
    return Supabase.instance.client.storage
        .from(AppConfig.supabaseBucket)
        .createSignedUrl(path, 300);
  }

  Future<void> closeShiftEarly({
    required AppUser coordinator,
    required DtrRecord record,
    required String reason,
    String? actualTime,
  }) async {
    if (!coordinator.role.isStaff || reason.trim().length < 8) {
      throw StateError('A coordinator and a clear reason are required.');
    }
    await _dtrAttendanceRequest({
      'action': 'close_early',
      'recordId': record.id,
      'reason': reason.trim(),
      'actualTime': actualTime,
    });
  }

  Future<void> submitDtrResponse({
    required AppUser student,
    required DtrRecord record,
    required String response,
  }) async {
    if (student.role != UserRole.student || record.studentId != student.uid) {
      throw StateError('You can reply only to your own DTR review.');
    }
    if (response.trim().length < 8) {
      throw StateError('Add a short explanation before sending your reply.');
    }
    await _dtrAttendanceRequest({
      'action': 'revision_response',
      'recordId': record.id,
      'response': response.trim(),
    });
  }

  Future<void> _dtrAttendanceRequest(Map<String, Object?> payload) async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw StateError('Sign in again to continue.');
    final token = await firebaseUser.getIdToken(true);
    final response = await http
        .post(
          Uri.parse(AppConfig.dtrAttendanceApiUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 25));
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {}
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        body['error'] as String? ?? 'Attendance request failed.',
      );
    }
  }

  Future<void> saveRequirementDefinition({
    required AppUser actor,
    String? id,
    required String title,
    required String description,
    required String instructions,
    required String category,
    required DateTime dueDate,
    required String program,
    String? officialFormUrl,
    String? sampleFormUrl,
    PdfFormTemplate? pdfTemplate,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can configure requirement bins.',
      );
    }
    if (title.trim().isEmpty || category.trim().isEmpty) {
      throw ArgumentError('Requirement title and category are required.');
    }
    final reference = id == null
        ? _db.collection('requirement_definitions').doc()
        : _db.collection('requirement_definitions').doc(id);
    await reference.set({
      'title': title.trim(),
      'description': description.trim(),
      'instructions': instructions.trim(),
      'category': category.trim(),
      'dueDate': Timestamp.fromDate(dueDate),
      'program': program.trim().isEmpty ? 'All Programs' : program.trim(),
      'officialFormUrl': officialFormUrl?.trim(),
      'sampleFormUrl': sampleFormUrl?.trim(),
      'pdfTemplate': pdfTemplate?.toMap(),
      'active': true,
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _log(actor, 'Configured requirement bin: $title');
  }

  static void validateTemplatePdf(String name, Uint8List bytes) {
    if (!name.toLowerCase().endsWith('.pdf') ||
        bytes.length < 5 ||
        ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
      throw ArgumentError('Choose a valid PDF file.');
    }
    if (bytes.length > 5 * 1024 * 1024) {
      throw ArgumentError('Each template or sample must be at most 5 MB.');
    }
  }

  /// Shared blank templates and samples only; completed personal copies are
  /// generated locally and must never be uploaded into this shared folder.
  Future<PdfFormTemplate> savePdfFormTemplate({
    required AppUser actor,
    PdfFormTemplate? existing,
    PlatformFile? officialFile,
    PlatformFile? sampleFile,
    bool removeSample = false,
    required List<PdfTemplateField> fields,
  }) async {
    if (!actor.role.isStaff) {
      throw StateError('Only coordinators can configure PDF templates.');
    }
    if (officialFile == null && existing == null) {
      throw ArgumentError('Upload the blank official PDF first.');
    }
    if (fields.length > 200 ||
        fields.map((field) => field.name).toSet().length != fields.length) {
      throw ArgumentError('Use at most 200 fields with unique names.');
    }
    for (final file in [officialFile, sampleFile].whereType<PlatformFile>()) {
      validateTemplatePdf(file.name, await file.readAsBytes());
    }
    if (officialFile == null && sampleFile == null) {
      return PdfFormTemplate(
        officialPath: existing!.officialPath,
        officialName: existing.officialName,
        fields: fields,
        samplePath: removeSample ? null : existing.samplePath,
        sampleName: removeSample ? null : existing.sampleName,
      );
    }
    // Storage verifies the staff claim before allowing writes to shared forms.
    final account = FirebaseAuth.instance.currentUser;
    if (account == null || account.uid != actor.uid) {
      throw StateError('Sign in again before uploading forms.');
    }
    final token = await account.getIdToken();
    final response = await http
        .post(
          Uri.parse(AppConfig.staffClaimsApiUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Unable to verify coordinator access. Try signing in again.',
      );
    }
    await account.getIdTokenResult(true);
    final uploaded = <String>[];
    try {
      var officialPath = existing?.officialPath;
      var samplePath = removeSample ? null : existing?.samplePath;
      if (officialFile != null) {
        officialPath = await _uploadFile(
          ownerId: actor.uid,
          folder: 'form_templates',
          file: officialFile,
        );
        uploaded.add(officialPath);
      }
      if (sampleFile != null) {
        samplePath = await _uploadFile(
          ownerId: actor.uid,
          folder: 'form_templates',
          file: sampleFile,
        );
        uploaded.add(samplePath);
      }
      return PdfFormTemplate(
        officialPath: officialPath!,
        officialName: officialFile?.name ?? existing!.officialName,
        samplePath: samplePath,
        sampleName:
            sampleFile?.name ?? (removeSample ? null : existing?.sampleName),
        fields: fields,
      );
    } catch (_) {
      if (uploaded.isNotEmpty) {
        try {
          await Supabase.instance.client.storage
              .from(AppConfig.supabaseBucket)
              .remove(uploaded);
        } catch (_) {
          /* Keep the original upload error. */
        }
      }
      rethrow;
    }
  }

  Future<Uint8List> loadPdfTemplateFile(String path) async {
    final url = await createDownloadUrl(path);
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError('Unable to load this PDF. Try again.');
    }
    final bytes = response.bodyBytes;
    validateTemplatePdf('template.pdf', bytes);
    return bytes;
  }

  Future<void> setNotificationActive({
    required AppUser actor,
    required NotificationRecord notification,
    required bool active,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can manage notifications.',
      );
    }
    await _db.collection('notifications').doc(notification.id).update({
      'active': active,
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(
      actor,
      '${active ? 'Activated' : 'Deactivated'} notification: ${notification.title}',
    );
  }

  Future<void> updateNotification({
    required AppUser actor,
    required NotificationRecord notification,
    required String title,
    required String message,
    required String priority,
    DateTime? scheduledFor,
    String? linkUrl,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can edit notifications.',
      );
    }
    if (title.trim().isEmpty || message.trim().isEmpty) {
      throw ArgumentError('Notification title and message are required.');
    }
    await _db.collection('notifications').doc(notification.id).update({
      'title': title.trim(),
      'message': message.trim(),
      'priority': priority,
      'scheduledFor': scheduledFor == null
          ? null
          : Timestamp.fromDate(scheduledFor),
      'linkUrl': linkUrl?.trim().isEmpty == true ? null : linkUrl?.trim(),
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(actor, 'Edited notification: ${notification.title}');
  }

  Future<void> deleteNotification({
    required AppUser actor,
    required NotificationRecord notification,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can delete notifications.',
      );
    }
    await _db.collection('notifications').doc(notification.id).delete();
    await _log(actor, 'Deleted notification: ${notification.title}');
  }

  Future<void> addMoa({
    required AppUser actor,
    required String partnerName,
    required String moaNumber,
    required DateTime startDate,
    required DateTime endDate,
    required PlatformFile file,
    String? partnerId,
    List<String> programs = const [],
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    String? remarks,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can manage partner and MOA records.',
      );
    }
    if (partnerName.trim().isEmpty || moaNumber.trim().isEmpty) {
      throw ArgumentError('Partner name and MOA number are required.');
    }
    if (!endDate.isAfter(startDate)) {
      throw ArgumentError('The expiry date must be after the start date.');
    }
    final storagePath = await _uploadFile(
      ownerId: actor.uid,
      folder: 'moas',
      file: file,
    );
    await _db.collection('moas').add({
      'partnerName': partnerName.trim(),
      'partnerId': partnerId,
      'moaNumber': moaNumber.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'storagePath': storagePath,
      'fileName': file.name,
      'programs': programs,
      'contactName': contactName?.trim(),
      'contactEmail': contactEmail?.trim(),
      'contactPhone': contactPhone?.trim(),
      'remarks': remarks?.trim(),
      'manualStatus': null,
      'createdBy': actor.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(actor, 'Created MOA $moaNumber for $partnerName');
  }

  Future<void> renewMoa({
    required AppUser actor,
    required MoaRecord record,
    required DateTime endDate,
    PlatformFile? replacementFile,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can renew MOA records.',
      );
    }
    if (!endDate.isAfter(record.startDate)) {
      throw ArgumentError('The expiry date must be after the start date.');
    }

    final previousStoragePath = record.storagePath;
    String? storagePath = previousStoragePath;
    String? fileName = record.fileName;

    if (replacementFile != null) {
      storagePath = await _uploadFile(
        ownerId: actor.uid,
        folder: 'moas',
        file: replacementFile,
      );
      fileName = replacementFile.name;
    }

    await _db.collection('moas').doc(record.id).update({
      'endDate': Timestamp.fromDate(endDate),
      'storagePath': storagePath,
      'fileName': fileName,
      'manualStatus': null,
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Only remove the previous object after Firestore points to the new file.
    // A cleanup failure must not undo a successful replacement.
    if (replacementFile != null &&
        previousStoragePath != null &&
        previousStoragePath.isNotEmpty &&
        previousStoragePath != storagePath) {
      try {
        await Supabase.instance.client.storage
            .from(AppConfig.supabaseBucket)
            .remove([previousStoragePath]);
      } catch (_) {
        // Best-effort cleanup. The new MOA document is already authoritative.
      }
    }

    await _log(
      actor,
      replacementFile == null
          ? 'Renewed MOA ${record.moaNumber}'
          : 'Replaced MOA file for ${record.moaNumber}',
    );
  }

  Future<void> updateMoaDetails({
    required AppUser actor,
    required MoaRecord record,
    required String partnerName,
    String? partnerId,
    required String moaNumber,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> programs,
    required String contactName,
    required String contactEmail,
    required String contactPhone,
    required String remarks,
    required String? manualStatus,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can manage partner and MOA records.',
      );
    }
    if (partnerName.trim().isEmpty || moaNumber.trim().isEmpty) {
      throw ArgumentError('Partner name and reference number are required.');
    }
    if (!endDate.isAfter(startDate)) {
      throw ArgumentError('The expiration date must be after the signed date.');
    }
    await _db.collection('moas').doc(record.id).update({
      'partnerName': partnerName.trim(),
      'partnerId': partnerId,
      'moaNumber': moaNumber.trim(),
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'programs': programs,
      'contactName': contactName.trim(),
      'contactEmail': contactEmail.trim(),
      'contactPhone': contactPhone.trim(),
      'remarks': remarks.trim(),
      'manualStatus': manualStatus,
      'updatedBy': actor.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(actor, 'Updated MOA ${record.moaNumber}');
  }

  Future<void> deleteMoa({
    required AppUser actor,
    required MoaRecord record,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can delete MOA records.',
      );
    }
    await _db.collection('moas').doc(record.id).delete();
    if (record.storagePath != null && AppConfig.hasSupabaseConfig) {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseBucket)
          .remove([record.storagePath!]);
    }
    await _log(actor, 'Deleted MOA ${record.moaNumber}');
  }

  Future<void> assignStudent({
    required AppUser actor,
    required AppUser student,
    required AppUser? coordinator,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can assign interns to Program Coordinators.',
      );
    }
    if (student.role != UserRole.student) {
      throw ArgumentError('Only student intern profiles can be assigned.');
    }
    if (coordinator != null && coordinator.role != UserRole.coordinator) {
      throw ArgumentError('The selected account is not a Program Coordinator.');
    }

    final placement = _db.collection('internship_profiles').doc(student.uid);
    await _db.runTransaction((transaction) async {
      final profile = await transaction.get(placement);
      transaction.update(_db.collection('users').doc(student.uid), {
        'coordinatorId': coordinator?.uid,
        'coordinatorName': coordinator?.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (profile.data()?['archived'] != true) {
        transaction.set(placement, {
          'coordinatorId': coordinator?.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    // Keep existing records aligned with the newly assigned coordinator so
    // Program Coordinator queries and security rules remain consistent.
    await _backfillCoordinatorAssignment(
      studentId: student.uid,
      coordinatorId: coordinator?.uid,
    );

    await _log(
      actor,
      coordinator == null
          ? 'Removed Program Coordinator assignment for ${student.displayName}'
          : 'Assigned ${student.displayName} to ${coordinator.displayName}',
    );

    if (coordinator != null) {
      await _createTargetedNotification(
        actor: actor,
        targetUserId: coordinator.uid,
        targetRole: UserRole.coordinator.value,
        title: 'New intern assigned',
        message:
            '${student.displayName} has been assigned to your internship group.',
        type: 'assignment',
        relatedId: student.uid,
      );
      await _createTargetedNotification(
        actor: actor,
        targetUserId: student.uid,
        targetRole: UserRole.student.value,
        title: 'Program Coordinator assigned',
        message: '${coordinator.displayName} is now your Program Coordinator.',
        type: 'assignment',
        relatedId: coordinator.uid,
      );
    }
  }

  Future<void> reviewCoordinatorRegistration({
    required AppUser actor,
    required AppUser target,
    required bool approve,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can review coordinator requests.',
      );
    }
    if (target.role != UserRole.coordinator ||
        target.approvalStatus != 'pending') {
      throw StateError('This coordinator request is no longer pending.');
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != actor.uid) {
      throw StateError(
        'Your CAS College Coordinator / SIP Admin session has expired. Sign in again.',
      );
    }
    final token = await currentUser.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw StateError(
        'Unable to refresh the CAS College Coordinator / SIP Admin security token.',
      );
    }

    final endpoint = Uri.parse(AppConfig.coordinatorApprovalApiUrl);
    http.Response response;
    try {
      response = await http.post(
        endpoint,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'uid': target.uid,
          'action': approve ? 'approve' : 'reject',
        }),
      );
    } catch (error) {
      throw StateError(
        'The coordinator approval service could not be reached. For local '
        'testing, start tools/approval_server.mjs and set '
        'COORDINATOR_APPROVAL_API_URL in config/local.json. On Vercel, deploy '
        'the included /api/coordinator-approval endpoint. Details: $error',
      );
    }

    Map<String, dynamic>? payload;
    try {
      payload = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      payload = null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = payload?['error']?.toString();
      throw StateError(
        message == null || message.isEmpty
            ? 'Coordinator approval failed (${response.statusCode}).'
            : message,
      );
    }

    await _log(
      actor,
      '${approve ? 'Approved' : 'Rejected'} coordinator registration for ${target.email}',
    );
  }

  Future<void> setUserActive({
    required AppUser actor,
    required AppUser target,
    required bool active,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can change account status.',
      );
    }
    if (actor.uid == target.uid && !active) {
      throw StateError('You cannot deactivate your own account.');
    }
    await _db.collection('users').doc(target.uid).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _log(
      actor,
      '${active ? 'Activated' : 'Deactivated'} ${target.email}',
    );
  }

  Future<String> createSupervisorEvaluation({
    required AppUser actor,
    required AppUser student,
    required String companyName,
    required String supervisorName,
    required String supervisorEmail,
    required String templatePath,
    int validDays = 14,
  }) async {
    if (!actor.role.isStaff) {
      throw StateError(
        'Student interns cannot create supervisor evaluation links.',
      );
    }
    await _assertCanManageStudent(actor, student.uid);
    if (student.role != UserRole.student ||
        companyName.trim().isEmpty ||
        supervisorName.trim().isEmpty ||
        !supervisorEmail.contains('@') ||
        validDays < 1 ||
        validDays > 60) {
      throw ArgumentError('Complete all supervisor evaluation details.');
    }
    if (student.academicYear?.trim().isEmpty ?? true) {
      throw StateError(
        'The student academic year is not set. Update the internship profile before creating an evaluation.',
      );
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid != actor.uid) {
      throw StateError(
        'Sign in with your staff account to create an evaluation.',
      );
    }

    final idToken = await currentUser.getIdToken(true);
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Your staff session has expired. Sign in again.');
    }

    final response = await http.post(
      Uri.parse(AppConfig.evaluationApiUrl),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'action': 'create',
        'studentId': student.uid,
        'companyName': companyName.trim(),
        'supervisorName': supervisorName.trim(),
        'supervisorEmail': supervisorEmail.trim().toLowerCase(),
        'templatePath': templatePath,
        'validDays': validDays,
      }),
    );

    final payload = response.body.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 201) {
      throw StateError(
        payload['error'] as String? ?? 'Unable to create the evaluation link.',
      );
    }

    final token = payload['token'];
    if (token is! String || token.isEmpty) {
      throw StateError('Evaluation service did not return a link token.');
    }
    await _log(
      actor,
      'Created supervisor evaluation for ${student.displayName}',
    );
    return token;
  }

  Future<Uint8List> evaluationPdf(
    Map<String, dynamic> request, {
    bool staff = false,
  }) async {
    final token = staff
        ? await FirebaseAuth.instance.currentUser?.getIdToken()
        : null;
    final link = await _evaluationAction(request, bearer: token);
    final response = await http.get(Uri.parse(link['url'] as String));
    if (response.statusCode != 200) {
      throw StateError('Unable to open the evaluation PDF.');
    }
    return response.bodyBytes;
  }

  Future<String> uploadEvaluationPdf(
    Map<String, dynamic> credentials,
    Uint8List bytes,
  ) async {
    final data = await _evaluationAction({
      ...credentials,
      'action': 'uploadPdf',
    });
    final response = await http.put(
      Uri.parse(data['url'] as String),
      headers: {'Content-Type': 'application/pdf'},
      body: bytes,
    );
    if (response.statusCode ~/ 100 != 2) {
      throw StateError('Unable to upload the evaluation PDF.');
    }
    return data['uploadId'] as String;
  }

  Future<void> submitSupervisorEvaluation({
    required String token,
    required String supervisorEmail,
    required String proof,
    required Map<String, int> ratings,
    required String comments,
    String? uploadId,
  }) async {
    await _evaluationAction({
      'action': 'submit',
      'token': token,
      'email': supervisorEmail.trim(),
      'proof': proof,
      if (uploadId != null) 'uploadId': uploadId else 'ratings': ratings,
      'confirmed': true,
      'comments': comments.trim(),
    });
  }

  Future<void> logReportGeneration({
    required AppUser actor,
    required String format,
    required int rowCount,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can generate college-wide reports.',
      );
    }
    final rangeLabel = startDate == null || endDate == null
        ? 'all dates'
        : '${startDate.year}-${startDate.month}-${startDate.day} to '
              '${endDate.year}-${endDate.month}-${endDate.day}';
    await _log(
      actor,
      'Generated ${format.toUpperCase()} internship report ($rowCount row(s), $rangeLabel)',
    );
  }

  Future<void> archiveAcademicYear({
    required AppUser actor,
    required int startYear,
  }) async {
    if (actor.role != UserRole.admin) {
      throw StateError(
        'Only the CAS College Coordinator / SIP Admin can archive academic-year records.',
      );
    }
    final end = DateTime(startYear + 1, 6, 1);
    if (end.isAfter(DateTime.now())) {
      throw StateError(
        'The active or a future academic year cannot be archived.',
      );
    }

    final academicYear = '$startYear-${startYear + 1}';
    final profileSnapshot = await _db
        .collection('internship_profiles')
        .where('academicYear', isEqualTo: academicYear)
        .get();

    final completedStudents = profileSnapshot.docs
        .where((doc) {
          final data = doc.data();
          return data['archived'] != true &&
              InternshipStageLabel.parse(data['status'] as String?) ==
                  InternshipStage.completed;
        })
        .map((doc) => doc.id)
        .toSet();

    if (completedStudents.isEmpty) {
      throw StateError(
        'No completed internship records are eligible for archiving in AY $academicYear.',
      );
    }

    final requirementSnapshot = await _db
        .collection('requirements')
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final dtrSnapshot = await _db
        .collection('dtr_entries')
        .where('academicYear', isEqualTo: academicYear)
        .get();
    final evaluationSnapshot = await _db
        .collection('supervisor_evaluations')
        .where('academicYear', isEqualTo: academicYear)
        .get();

    final references = <DocumentReference<Map<String, dynamic>>>[];
    var requirementCount = 0;
    var dtrCount = 0;
    var evaluationCount = 0;

    for (final doc in requirementSnapshot.docs) {
      final data = doc.data();
      if (data['archived'] == true ||
          !completedStudents.contains(data['studentId'])) {
        continue;
      }
      if (ReviewStatusLabel.parse(data['status'] as String?) !=
          ReviewStatus.verified) {
        throw StateError(
          'All requirements must be verified before AY $academicYear can be archived.',
        );
      }
      final path = data['storagePath'];
      final parts = path is String ? path.split('/') : const <String>[];
      if (parts.length != 3 ||
          parts.first != data['studentId'] ||
          parts[1] != 'requirements' ||
          parts.last.isEmpty) {
        throw StateError(
          'Restore the retained submission file for record ${doc.id} before archiving.',
        );
      }
      references.add(doc.reference);
      requirementCount++;
    }

    for (final doc in dtrSnapshot.docs) {
      final data = doc.data();
      if (data['archived'] == true ||
          !completedStudents.contains(data['studentId'])) {
        continue;
      }
      if (ReviewStatusLabel.parse(data['status'] as String?) !=
          ReviewStatus.verified) {
        throw StateError(
          'All DTR entries must be approved before AY $academicYear can be archived.',
        );
      }
      if (DtrRecord.fromDoc(doc).renderedHours <= 0) {
        throw StateError(
          'Resolve the invalid attendance record ${doc.id} before archiving.',
        );
      }
      references.add(doc.reference);
      dtrCount++;
    }

    for (final doc in evaluationSnapshot.docs) {
      final data = doc.data();
      if (data['archived'] == true ||
          !completedStudents.contains(data['studentId'])) {
        continue;
      }
      if (data['status'] != 'submitted') {
        throw StateError(
          'Supervisor evaluations must be submitted before AY $academicYear can be archived.',
        );
      }
      references.add(doc.reference);
      evaluationCount++;
    }

    for (final profile in profileSnapshot.docs) {
      if (!completedStudents.contains(profile.id)) continue;
      references.add(profile.reference);
    }

    for (var offset = 0; offset < references.length; offset += 450) {
      final batch = _db.batch();
      final endIndex = min(offset + 450, references.length);
      for (final reference in references.sublist(offset, endIndex)) {
        batch.update(reference, {
          'archived': true,
          'academicYear': academicYear,
          'archivedBy': actor.uid,
          'archivedAt': FieldValue.serverTimestamp(),
          if (reference.parent.id == 'internship_profiles')
            'status': InternshipStage.archived.value,
        });
      }
      await batch.commit();
    }

    await _db.collection('academic_archives').add({
      'academicYear': academicYear,
      'requirementCount': requirementCount,
      'dtrCount': dtrCount,
      'evaluationCount': evaluationCount,
      'studentCount': completedStudents.length,
      'createdBy': actor.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _log(actor, 'Archived academic year $academicYear');
  }

  Future<void> _log(AppUser actor, String action) =>
      _db.collection('activity_logs').add({
        'userId': actor.uid,
        'userName': actor.displayName,
        'action': action,
        'createdAt': FieldValue.serverTimestamp(),
      });

  void _scheduleRequirementFollowUps({
    required AppUser user,
    required String activity,
    required String notificationTitle,
    required String notificationMessage,
    required String relatedId,
  }) {
    unawaited(() async {
      await _runRequirementFollowUp('activity log', () => _log(user, activity));
      final coordinatorId = user.coordinatorId;
      if (coordinatorId != null && coordinatorId.isNotEmpty) {
        await _runRequirementFollowUp(
          'coordinator notification',
          () => _createTargetedNotification(
            actor: user,
            targetUserId: coordinatorId,
            targetRole: UserRole.coordinator.value,
            title: notificationTitle,
            message: notificationMessage,
            type: 'document_submission',
            relatedId: relatedId,
          ),
        );
      }
    }());
  }

  Future<void> _runRequirementFollowUp(
    String description,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      developer.log(
        'Could not finish requirement $description.',
        name: 'PracticumRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _queueLog(WriteBatch batch, AppUser actor, String action) {
    batch.set(_db.collection('activity_logs').doc(), {
      'userId': actor.uid,
      'userName': actor.displayName,
      'action': action,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _queueTargetedNotification({
    required WriteBatch batch,
    required AppUser actor,
    required String targetUserId,
    required String targetRole,
    required String title,
    required String message,
    required String type,
    required String relatedId,
  }) {
    batch.set(_db.collection('notifications').doc(), {
      'title': title,
      'message': message,
      'targetRole': 'user:$targetUserId',
      'targetUserId': targetUserId,
      'type': type,
      'relatedId': relatedId,
      'priority': 'normal',
      'scheduledFor': null,
      'linkUrl': null,
      'readBy': <String>[],
      'createdBy': actor.uid,
      'read': false,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _createTargetedNotification({
    required AppUser actor,
    required String targetUserId,
    required String targetRole,
    required String title,
    required String message,
    required String type,
    required String relatedId,
  }) async {
    if (targetUserId.isEmpty) {
      return;
    }
    await sendNotification(
      actor: actor,
      title: title,
      message: message,
      targetRole: targetRole,
      targetUserId: targetUserId,
      type: type,
      relatedId: relatedId,
    );
  }

  Future<void> _assertCanManageStudent(AppUser actor, String studentId) async {
    if (actor.role == UserRole.admin) {
      return;
    }
    if (actor.role != UserRole.coordinator) {
      throw StateError('This action is restricted to authorized staff.');
    }
    final snapshot = await _db.collection('users').doc(studentId).get();
    final data = snapshot.data();
    if (data == null ||
        data['role'] != UserRole.student.value ||
        data['coordinatorId'] != actor.uid) {
      throw StateError(
        'This student intern is not assigned to your Program Coordinator account.',
      );
    }
  }

  Future<void> _backfillCoordinatorAssignment({
    required String studentId,
    required String? coordinatorId,
  }) async {
    const collections = [
      'requirements',
      'dtr_entries',
      'supervisor_evaluations',
    ];
    for (final collection in collections) {
      final snapshot = await _db
          .collection(collection)
          .where('studentId', isEqualTo: studentId)
          .get();
      final active = snapshot.docs
          .where((doc) => doc.data()['archived'] != true)
          .toList();
      for (var offset = 0; offset < active.length; offset += 450) {
        final batch = _db.batch();
        final endIndex = min(offset + 450, active.length);
        for (final doc in active.sublist(offset, endIndex)) {
          batch.update(doc.reference, {
            'coordinatorId': coordinatorId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    }
  }

  Future<void> _syncInternshipStage(
    String studentId, {
    required AppUser actor,
    WriteBatch? batch,
    String? reviewCollection,
    String? reviewId,
    ReviewStatus? reviewStatus,
    Map<String, dynamic>? profileChanges,
    Map<String, dynamic>? userChanges,
  }) async {
    if (studentId.isEmpty) return;

    final userSnapshot = await _db.collection('users').doc(studentId).get();
    final storedUser = userSnapshot.data();
    final userData = storedUser == null
        ? null
        : {...storedUser, ...?userChanges};
    if (userData == null || userData['role'] != UserRole.student.value) {
      return;
    }

    final profileReference = _db
        .collection('internship_profiles')
        .doc(studentId);
    final profileSnapshot = await profileReference.get();
    final profileData = {...?profileSnapshot.data(), ...?profileChanges};
    final writes = batch ?? _db.batch();
    Query<Map<String, dynamic>> studentQuery(String collection) {
      Query<Map<String, dynamic>> query = _db
          .collection(collection)
          .where('studentId', isEqualTo: studentId);
      if (actor.role == UserRole.coordinator) {
        query = query.where('coordinatorId', isEqualTo: actor.uid);
      }
      return query;
    }

    ReviewStatus? requirementStatus(RequirementRecord? record) =>
        reviewCollection == 'requirements' && record?.id == reviewId
        ? reviewStatus
        : record?.status;

    if (profileSnapshot.data()?['archived'] == true) return;

    final currentAcademicYear =
        (userData['academicYear'] as String? ??
                profileData['academicYear'] as String? ??
                '')
            .trim();

    final program = userData['program'] as String?;
    final definitionsSnapshot = await _db
        .collection('requirement_definitions')
        .get();
    final definitions = definitionsSnapshot.docs
        .map(RequirementDefinition.fromDoc)
        .where(
          (definition) =>
              definition.active && definition.appliesToProgram(program),
        )
        .toList();

    final requirementSnapshot = await studentQuery('requirements').get();
    final activeRequirements = requirementSnapshot.docs
        .map(RequirementRecord.fromDoc)
        .where(
          (record) =>
              !record.archived &&
              record.academicYear?.trim() == currentAcademicYear &&
              currentAcademicYear.isNotEmpty,
        )
        .toList();

    RequirementRecord? recordFor(RequirementDefinition definition) {
      final candidates =
          activeRequirements
              .where(
                (record) =>
                    record.definitionId == definition.id ||
                    (record.definitionId == null &&
                        record.title.trim().toLowerCase() ==
                            definition.title.trim().toLowerCase()),
              )
              .toList()
            ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return candidates.isEmpty ? null : candidates.first;
    }

    final deploymentDefinitions = definitions
        .where((definition) => definition.blocksDeployment)
        .toList();
    final prerequisites = deploymentDefinitions.isEmpty
        ? definitions
        : deploymentDefinitions;
    final completionDefinitions = definitions
        .where((definition) => definition.isCompletionRequirement)
        .toList();

    final allSubmitted =
        prerequisites.isNotEmpty &&
        prerequisites.every((definition) => recordFor(definition) != null);
    final allVerified =
        allSubmitted &&
        prerequisites.every(
          (definition) =>
              requirementStatus(recordFor(definition)) == ReviewStatus.verified,
        );

    InternshipStage nextStage;
    if (!allSubmitted) {
      nextStage = InternshipStage.pendingRequirements;
    } else if (!allVerified) {
      nextStage = InternshipStage.forVerification;
    } else {
      final placementStatus =
          (profileData['placementStatus'] as String? ?? 'Unassigned')
              .toLowerCase();
      final placementConfirmed =
          placementStatus.contains('confirm') ||
          placementStatus.contains('deploy') ||
          placementStatus.contains('ongoing') ||
          placementStatus.contains('active');

      if (!placementConfirmed) {
        nextStage = InternshipStage.readyForDeployment;
      } else {
        final dtrSnapshot = await studentQuery('dtr_entries').get();
        final approvedHours = dtrSnapshot.docs
            .map(DtrRecord.fromDoc)
            .where(
              (record) =>
                  !record.archived &&
                  (reviewCollection == 'dtr_entries' && record.id == reviewId
                          ? reviewStatus
                          : record.status) ==
                      ReviewStatus.verified &&
                  record.academicYear?.trim() == currentAcademicYear &&
                  currentAcademicYear.isNotEmpty,
            )
            .fold<double>(0, (total, record) => total + record.renderedHours);

        final requiredHours =
            (profileData['requiredHours'] as num?)?.toDouble() ?? 400;

        bool evaluationSubmitted;

        if (actor.role == UserRole.student) {
          // Students may check only their own non-confidential status.
          if (studentId != actor.uid) {
            throw StateError('Cannot check another student evaluation status.');
          }

          final statusSnapshot = await _db
              .collection('evaluation_status')
              .where('studentId', isEqualTo: studentId)
              .get();

          evaluationSubmitted =
              currentAcademicYear.isNotEmpty &&
              statusSnapshot.docs.any(
                (doc) =>
                    doc.data()['academicYear'] == currentAcademicYear &&
                    doc.data()['status'] == 'submitted',
              );
        } else {
          // Authorized staff retain access to confidential evaluations.
          Query<Map<String, dynamic>> evaluationQuery = _db
              .collection('supervisor_evaluations')
              .where('studentId', isEqualTo: studentId);

          if (actor.role == UserRole.coordinator) {
            evaluationQuery = evaluationQuery.where(
              'coordinatorId',
              isEqualTo: actor.uid,
            );
          }

          final evaluationSnapshot = await evaluationQuery.get();

          evaluationSubmitted =
              currentAcademicYear.isNotEmpty &&
              evaluationSnapshot.docs.any(
                (doc) =>
                    doc.data()['archived'] != true &&
                    doc.data()['academicYear'] == currentAcademicYear &&
                    doc.data()['status'] == 'submitted',
              );
        }

        final completionRequirementsVerified =
            completionDefinitions.isEmpty ||
            completionDefinitions.every(
              (definition) =>
                  requirementStatus(recordFor(definition)) ==
                  ReviewStatus.verified,
            );

        nextStage =
            approvedHours >= requiredHours &&
                evaluationSubmitted &&
                completionRequirementsVerified
            ? InternshipStage.completed
            : InternshipStage.ongoingInternship;
      }
    }

    final previousStatus =
        profileSnapshot.data()?['status'] as String? ??
        InternshipStage.pendingRequirements.value;
    final nextStatus = nextStage.value;
    final coordinatorId =
        userData['coordinatorId'] as String? ??
        profileData['coordinatorId'] as String?;
    final academicYear =
        userData['academicYear'] as String? ??
        profileData['academicYear'] as String?;

    writes.set(profileReference, {
      'status': nextStatus,
      'coordinatorId': coordinatorId,
      'academicYear': academicYear,
      'archived': false,
      if (nextStage == InternshipStage.completed &&
          profileData['completedAt'] == null)
        'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (previousStatus != nextStatus && actor.role.isStaff) {
      _queueTargetedNotification(
        batch: writes,
        actor: actor,
        targetUserId: studentId,
        targetRole: UserRole.student.value,
        title: 'Internship status updated',
        message: 'Your internship status is now $nextStatus.',
        type: 'status_update',
        relatedId: studentId,
      );
    }
    if (batch == null) await writes.commit();
  }

  Future<String> _uploadFile({
    required String ownerId,
    required String folder,
    required PlatformFile file,
  }) async {
    if (!AppConfig.hasSupabaseConfig) {
      throw StateError(AppConfig.missingSupabaseMessage);
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Sign in again before uploading a file.');
    }
    if (ownerId != firebaseUser.uid) {
      throw StateError(
        'This profile does not match the signed-in Firebase account. Sign out '
        'and back in; if the issue continues, check that the profile UID matches '
        'the Firebase Authentication UID.',
      );
    }

    // Refresh the Firebase ID token so Supabase receives the latest session.
    // Storage checks the roster activation claims as well as folder ownership.
    await firebaseUser.getIdTokenResult(true);
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$ownerId/$folder/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final bytes = await file.readAsBytes();
    if (folder == 'requirements' &&
        (bytes.isEmpty || bytes.length > 5 * 1024 * 1024)) {
      throw StateError('Each requirement file must be at most 5 MB.');
    }
    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeFor(file.extension),
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      if (error.statusCode == '403' &&
          error.message.contains('Header Parameter value not allowed')) {
        throw StateError(
          'Supabase is not accepting Firebase tokens yet. In the Supabase '
          'dashboard, add Firebase project practicumconnect-aa5d1 '
          'under Authentication > Third-Party Auth.',
        );
      }
      if (error.statusCode == '403' &&
          error.message.toLowerCase().contains('row-level security')) {
        throw StateError(
          'Supabase Storage blocked this upload because no insert policy '
          'matched. In the Supabase project connected to this app, run '
          'supabase_storage_policies.sql in the SQL Editor. The bucket must be '
          'PracticumConnectStorage, and the uploaded file path must start with '
          'the signed-in Firebase user ID. If you already ran the script, '
          'verify the project and bucket name, then retry.',
        );
      }
      rethrow;
    }
    return path;
  }

  Future<String> _uploadBytes({
    required String ownerId,
    required String folder,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!AppConfig.hasSupabaseConfig) {
      throw StateError(AppConfig.missingSupabaseMessage);
    }
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null || firebaseUser.uid != ownerId) {
      throw StateError('Sign in again before capturing your attendance photo.');
    }
    await firebaseUser.getIdTokenResult(true);
    final path =
        '$ownerId/$folder/${DateTime.now().microsecondsSinceEpoch}_$fileName';
    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: false),
          );
    } on StorageException catch (error) {
      if (error.statusCode == '403' &&
          error.message.toLowerCase().contains('row-level security')) {
        throw StateError(
          'Supabase Storage blocked the check-in photo. Verify the storage '
          'bucket and Firebase third-party authentication policy.',
        );
      }
      rethrow;
    }
    return path;
  }

  String _contentTypeFor(String? extension) => switch (extension
      ?.toLowerCase()) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => 'application/octet-stream',
  };
}
