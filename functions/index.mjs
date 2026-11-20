import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { deliverReminders, remindStudent } from './reminders.mjs';
import { reconcileStudent } from './stage.mjs';

initializeApp();
export const syncRequirementStage = onDocumentWritten(
  { document: 'requirements/{id}', retry: true },
  async (event) => {
    const ids = new Set([event.data?.before.data()?.studentId, event.data?.after.data()?.studentId]);
    for (const uid of ids)
      if (uid) {
        const db = getFirestore();
        await reconcileStudent(db, uid);
        await remindStudent(db, db.collection('users').doc(uid));
      }
  },
);

export const sendInternshipReminders = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Asia/Manila', retryCount: 3, timeoutSeconds: 540 },
  () => deliverReminders(getFirestore()),
);

export const syncReminderDefinition = onDocumentWritten(
  { document: 'requirement_definitions/{id}', retry: true, timeoutSeconds: 540 },
  () => deliverReminders(getFirestore()),
);

export const syncReminderAccount = onDocumentWritten(
  { document: 'users/{uid}', retry: true, timeoutSeconds: 540 },
  async (event) => {
    const before = event.data?.before.data(),
      after = event.data?.after.data();
    const relevant = [
      'role',
      'active',
      'approvalStatus',
      'enrollmentStatus',
      'displayName',
      'program',
      'academicYear',
      'coordinatorId',
      'reminderHours',
    ];
    if (!relevant.some((key) => before?.[key] !== after?.[key])) return;
    const db = getFirestore(),
      uid = event.params.uid;
    if ([before?.role, after?.role].includes('student'))
      await remindStudent(db, db.collection('users').doc(uid));
    if ([before?.role, after?.role].includes('coordinator')) await deliverReminders(db, new Date(), uid);
  },
);

export const syncReminderPlacement = onDocumentWritten(
  { document: 'internship_profiles/{uid}', retry: true },
  async (event) => {
    const before = event.data?.before.data(),
      after = event.data?.after.data();
    if (before?.status === after?.status && before?.archived === after?.archived) return;
    const db = getFirestore();
    await remindStudent(db, db.collection('users').doc(event.params.uid));
  },
);
