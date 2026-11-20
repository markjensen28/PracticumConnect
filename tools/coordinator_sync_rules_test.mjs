import { randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where, writeBatch } from 'firebase/firestore';

const env = await initializeTestEnvironment({ projectId: 'demo-sync-' + randomUUID().slice(0,8),
  firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync('firestore.rules', 'utf8') } });
try {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'staff'), { role: 'coordinator', active: true, approvalStatus: 'approved' });
    await setDoc(doc(db, 'users', 'student'), { role: 'student', enrollmentStatus: 'active', active: true, coordinatorId: 'staff' });
    await setDoc(doc(db, 'internship_profiles', 'student'), { coordinatorId: 'staff', status: 'For Verification' });
    for (const name of ['requirements', 'dtr_entries']) await setDoc(doc(db, name, 'record'), {
      studentId: 'student', coordinatorId: 'staff', status: 'pending', archived: false,
    });
    await setDoc(doc(db, 'requirements', 'archived'), {
      studentId: 'student', coordinatorId: 'staff', status: 'rejected', archived: true,
    });
  });
  const db = env.authenticatedContext('staff').firestore();
  for (const name of ['requirements', 'dtr_entries']) {
    await assertFails(getDocs(query(collection(db, name), where('studentId', '==', 'student'))));
    await assertSucceeds(getDocs(query(collection(db, name), where('studentId', '==', 'student'), where('coordinatorId', '==', 'staff'))));
    console.log('PASS: scoped ' + name + ' query succeeds; unscoped query denied');
  }
  const review = writeBatch(db);
  review.update(doc(db, 'requirements', 'record'), { status: 'verified', reviewedBy: 'staff' });
  review.set(doc(db, 'internship_profiles', 'student'), { status: 'Ready for Deployment', coordinatorId: 'staff' }, { merge: true });
  review.set(doc(db, 'notifications', 'feedback'), { targetRole: 'user:student', targetUserId: 'student', createdBy: 'staff' });
  review.set(doc(db, 'activity_logs', 'review'), { userId: 'staff', action: 'Review' });
  await assertSucceeds(review.commit());
  const denied = writeBatch(db);
  denied.update(doc(db, 'requirements', 'record'), { status: 'rejected' });
  denied.set(doc(db, 'activity_logs', 'invalid'), { userId: 'someone-else' });
  await assertFails(denied.commit());
  assert.equal((await getDoc(doc(db, 'requirements', 'record'))).data().status, 'verified');
  console.log('PASS: review/stage/feedback/audit batch accepted; failing batch rolls back');
  const student = env.authenticatedContext('student', {student_enrolled:true,email_verified:true}).firestore();
  await assertFails(updateDoc(doc(student, 'internship_profiles','student'),{status:'For Verification'}));
  await assertFails(updateDoc(doc(student, 'requirements', 'record'), { storagePath: 'student/requirements/replaced' }));
  await assertFails(updateDoc(doc(student, 'requirements', 'archived'), { status: 'pending' }));
  console.log('PASS: verified and archived submissions cannot be replaced');
} finally { await env.cleanup(); }
