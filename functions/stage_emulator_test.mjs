import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { reconcileStudent } from './stage.mjs';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
initializeApp({ projectId: 'demo-stage-' + randomUUID().slice(0, 8) });
const db = getFirestore(),
  uid = 'student';
const profile = db.doc('internship_profiles/student'),
  submission = db.doc('requirements/cv');
await db.doc('users/student').set({ role: 'student', academicYear: 'AY', coordinatorId: 'assigned' });
await db.doc('requirement_definitions/cv').set({ title: 'CV' });
await db.doc('requirement_definitions/report').set({ title: 'Final report' });
async function check(expected) {
  await reconcileStudent(db, uid);
  const snapshot = await profile.get();
  assert.equal(snapshot.get('status'), expected);
  await reconcileStudent(db, uid);
  assert.ok((await profile.get()).updateTime.isEqual(snapshot.updateTime));
}
await check('Pending Requirements');
await submission.set({ studentId: uid, academicYear: 'AY', definitionId: 'cv', status: 'pending' });
await check('For Verification');
await submission.update({ status: 'verified' });
await check('Ready for Deployment');
await profile.update({ placementStatus: 'Deployed', requiredHours: 1 });
await db
  .doc('requirements/report')
  .set({ studentId: uid, academicYear: 'AY', definitionId: 'report', status: 'pending' });
await check('Ongoing Internship');
await db.doc('requirements/report').update({ version: 2, status: 'pending' });
await check('Ongoing Internship');
await db.doc('requirements/report').update({ status: 'verified' });
await db
  .doc('dtr_entries/day')
  .set({
    studentId: uid,
    academicYear: 'AY',
    status: 'verified',
    date: Timestamp.fromMillis(0),
    breakMinutes: 0,
    timeIn: Timestamp.fromMillis(0),
    timeOut: Timestamp.fromMillis(3600000),
  });
await db
  .doc('supervisor_evaluations/supervisor')
  .set({ studentId: uid, academicYear: 'AY', status: 'submitted' });
await check('Completed');
await profile.update({ archived: true, status: 'Archived' });
await check('Archived');
console.log(
  'PASS: server stage reconciles committed submissions and resubmissions, preserves archive and ignores duplicate events.',
);
