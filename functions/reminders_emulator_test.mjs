import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { deliverReminders, remindStudent } from './reminders.mjs';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
initializeApp({ projectId: 'demo-remind-' + randomUUID().slice(0, 8) });
const db = getFirestore();
const student = db.doc('users/student'),
  staff = db.doc('users/staff'),
  def = db.doc('requirement_definitions/cv');
const now = new Date('2026-11-01T03:00:00Z'),
  hour = 3600000;
const deadline = new Date('2026-11-05T08:30:00Z');
await student.set({
  role: 'student',
  active: true,
  enrollmentStatus: 'active',
  academicYear: '2026-2027',
  program: 'Arts',
  coordinatorId: staff.id,
});
await staff.set({ role: 'coordinator', active: true, approvalStatus: 'approved' });
await def.set({ title: 'CV', program: 'All Programs', dueDate: Timestamp.fromDate(deadline) });
await db
  .doc('requirement_definitions/other')
  .set({ title: 'Science report', program: 'Science', dueDate: Timestamp.fromDate(deadline) });
const inbox = async () => (await db.collection('notifications').get()).docs;
async function onlyNotice(target, expectedTime) {
  const all = await inbox();
  assert.equal(all.length, 1);
  assert.equal(all[0].get('targetUserId'), target);
  assert.equal(all[0].get('scheduledFor').toMillis(), expectedTime);
  return all[0];
}
await Promise.all([deliverReminders(db, now), deliverReminders(db, now)]);
const defaultNotice = await onlyNotice(student.id, +deadline - 72 * hour);
for (const hours of [24, 48, 3]) {
  await student.update({ reminderHours: hours });
  await remindStudent(db, student, now);
  assert.equal((await onlyNotice(student.id, +deadline - hours * hour)).id, defaultNotice.id);
}
const record = db.doc('requirements/r');
await record.set({
  studentId: student.id,
  coordinatorId: staff.id,
  definitionId: 'cv',
  academicYear: '2026-2027',
  status: 'pending',
  archived: false,
  version: 1,
  submittedAt: Timestamp.fromDate(now),
});
await remindStudent(db, student, now);
await onlyNotice(staff.id, +now + 48 * hour);
await staff.update({ reminderHours: 6 });
await deliverReminders(db, now, staff.id);
const verification = await onlyNotice(staff.id, +now + 6 * hour);
await remindStudent(db, student, new Date(+now + 7 * hour));
assert.equal((await inbox())[0].id, verification.id);
await verification.ref.delete();
await deliverReminders(db, new Date(+now + 8 * hour));
assert.equal((await inbox()).length, 0);
await record.update({ status: 'needs_revision' });
await remindStudent(db, student, new Date(+now + 9 * hour));
await onlyNotice(student.id, +deadline - 3 * hour);
await record.update({
  status: 'under_review',
  version: 2,
  submittedAt: Timestamp.fromMillis(+now + 10 * hour),
});
await remindStudent(db, student, new Date(+now + 10 * hour));
await onlyNotice(staff.id, +now + 16 * hour);
await record.update({ status: 'verified' });
await remindStudent(db, student, new Date(+now + 11 * hour));
assert.equal((await inbox()).length, 0);
await record.delete();
await deliverReminders(db, new Date(+deadline + 1));
assert.equal((await inbox()).length, 0);
await def.update({ dueDate: Timestamp.fromDate(new Date('2026-11-04T16:00:00Z')) }); // Manila midnight
await deliverReminders(db, now);
await onlyNotice(student.id, Date.parse('2026-11-05T15:59:00Z') - 3 * hour);
await db.doc('internship_profiles/student').set({ archived: true });
await deliverReminders(db, now);
assert.equal((await inbox()).length, 0);
console.log(
  'PASS personalized due and review times, rescheduling, same-day deadlines, role targeting, retries and cancellation',
);
