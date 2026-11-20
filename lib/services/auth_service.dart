import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/app_config.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';

class AuthService {
  Future<AppUser?> restoreUser() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;
    return _loadProfile(firebaseUser);
  }

  Future<AppUser> signIn(String email, String password) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _normalizeEmail(email),
      password: password,
    );
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw StateError('Firebase did not return a signed-in user.');
    }
    return _loadProfile(firebaseUser);
  }

  Future<void> registerCoordinatorRequest({
    required String email,
    required String password,
    required String displayName,
    required String staffId,
    required String department,
  }) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
          email: _normalizeEmail(email),
          password: password,
        );
    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw StateError('Firebase did not return the new coordinator account.');
    }

    try {
      await firebaseUser.updateDisplayName(displayName.trim());
      await firebaseUser.getIdToken(true);
      final profileEmail = _emailForProfile(firebaseUser, email);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firebaseUser.uid)
          .set({
            'email': profileEmail,
            'displayName': displayName.trim(),
            'role': UserRole.coordinator.value,
            'studentNumber': null,
            'staffId': staffId.trim(),
            'department': department.trim(),
            'approvalStatus': 'pending',
            'active': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      // A pending coordinator must not remain signed in. The administrator will
      // review the request and the account becomes usable only after approval.
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      try {
        await firebaseUser.delete();
      } catch (_) {
        // If Firebase has already invalidated the session, the Firestore rules
        // still keep the unapproved account inactive.
      }
      rethrow;
    }
  }

  Future<AppUser> _loadProfile(User firebaseUser) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(firebaseUser.uid)
        .get();
    if (!snapshot.exists) {
      await FirebaseAuth.instance.signOut();
      throw StateError(
        'No authorized profile was found. Ask your school administrator to check your roster invitation.',
      );
    }
    var profile = AppUser.fromMap(firebaseUser.uid, snapshot.data()!);

    if (profile.role == UserRole.student) {
      try {
        final enrollment = snapshot.data()?['enrollmentStatus'];
        if (enrollment != 'pending' && enrollment != 'active') {
          throw StateError(
            'Ask your coordinator for your official roster invitation.',
          );
        }
        await firebaseUser.reload();
        final current = FirebaseAuth.instance.currentUser!;
        if (!current.emailVerified) {
          await current.sendEmailVerification();
          throw StateError(
            'Check your inbox for the verification link, then sign in again.',
          );
        }
        final token = await current.getIdTokenResult(true);
        if (enrollment == 'pending' ||
            token.claims?['student_enrolled'] != true) {
          final response = await http.post(
            Uri.parse(
              AppConfig.coordinatorApprovalApiUrl,
            ).resolve('/api/student-activation'),
            headers: {'Authorization': 'Bearer ${token.token}'},
          );
          if (response.statusCode != 200) {
            throw StateError(
              (jsonDecode(response.body) as Map)['error'] ??
                  'Unable to activate your account.',
            );
          }
          await current.getIdToken(true);
          final refreshed = await snapshot.reference.get();
          profile = AppUser.fromMap(refreshed.id, refreshed.data()!);
        }
      } catch (_) {
        await FirebaseAuth.instance.signOut();
        rethrow;
      }
    }

    if (profile.isPendingCoordinator) {
      await FirebaseAuth.instance.signOut();
      throw StateError(
        'Your coordinator registration is awaiting CAS College Coordinator / SIP Admin verification. '
        'You can sign in after a CAS College Coordinator / SIP Admin approves your request.',
      );
    }
    if (profile.isRejectedCoordinator) {
      await FirebaseAuth.instance.signOut();
      throw StateError(
        'Your coordinator registration was not approved. Contact the school '
        'administrator if you believe this is a mistake.',
      );
    }
    if (!profile.active) {
      await FirebaseAuth.instance.signOut();
      throw StateError('This account has been disabled.');
    }
    return profile;
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  String _emailForProfile(User firebaseUser, String fallback) =>
      firebaseUser.email?.trim() ?? _normalizeEmail(fallback);
}
