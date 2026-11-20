import { createHash } from 'node:crypto';
import { FieldPath, FieldValue, Timestamp } from 'firebase-admin/firestore';

const hour = 3600000;
const day = 24 * hour;
function hoursFor(account, fallback) {
  const value = account?.reminderHours;
  return Number.isInteger(value) && value >= 1 && value <= 720 ? value : fallback;
}
// Date-picker deadlines store local midnight. A date-only assignment is due
// at the end of that school day; retain explicit times on timed assignments.
function deadlineTime(date) {
  return (date.getTime() + 8 * hour) % day === 0 ? date.getTime() + day - 60000 : date.getTime();
}
const schoolDate = new Intl.DateTimeFormat('en-CA', {
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  timeZone: 'Asia/Manila',
});
const normalized = (title) =>
  String(title ?? '')
    .trim()
    .toLowerCase();

export function remindersFor({ student, profile, coordinator, definitions, submissions, now }) {
  const year = student?.academicYear?.trim();
  if (
    !student?.active ||
    student.role !== 'student' ||
    student.enrollmentStatus !== 'active' ||
    !year ||
    profile?.archived ||
    ['archived', 'completed', 'complete'].includes(normalized(profile?.status))
  )
    return [];
  const assigned = definitions.filter(
    (d) =>
      d.active !== false &&
      (!d.program?.trim() || d.program === 'All Programs' || d.program === student.program),
  );
  const byTitle = new Map();
  for (const def of assigned) {
    const key = normalized(def.title);
    byTitle.set(key, byTitle.has(key) ? null : def.id);
  }
  const latest = new Map();
  for (const r of submissions) {
    if (r.archived || r.studentId !== student.id || r.academicYear?.trim() !== year) continue;
    const id = r.definitionId || byTitle.get(normalized(r.title));
    const prior = latest.get(id);
    const time = r.submittedAt?.toMillis?.() ?? 0;
    const previousTime = prior?.submittedAt?.toMillis?.() ?? 0;
    if (
      !prior ||
      time > previousTime ||
      (time === previousTime &&
        ((r.version ?? 1) > (prior.version ?? 1) ||
          ((r.version ?? 1) === (prior.version ?? 1) && r.id > prior.id)))
    )
      latest.set(id, r);
  }
  const notices = [];

  for (const def of assigned) {
    const record = latest.get(def.id);
    const due = def.dueDate?.toDate?.();
    if (!record || ['needs_revision', 'rejected'].includes(record.status)) {
      if (!due) continue;
      const deadline = deadlineTime(due);
      if (now.getTime() > deadline) continue;
      const date = schoolDate.format(deadline);
      const at = deadline - hoursFor(student, 72) * hour;
      notices.push({
        key: ['deadline', student.id, year, def.id, deadline],
        at,
        target: student.id,
        type: 'deadline',
        relatedId: def.id,
        title: 'Requirement deadline reminder',
        message: `${record ? 'Resubmit' : 'Submit'} ${def.title} by ${date}.`,
      });
    } else if (
      ['pending', 'under_review'].includes(record.status) &&
      Number.isFinite(record.submittedAt?.toMillis?.()) &&
      coordinator?.active === true &&
      coordinator.role === 'coordinator' &&
      coordinator.approvalStatus === 'approved' &&
      student.coordinatorId &&
      record.coordinatorId === student.coordinatorId
    ) {
      notices.push({
        at: record.submittedAt.toMillis() + hoursFor(coordinator, 48) * hour,
        key: ['verification', student.id, year, record.id, record.version ?? 1, student.coordinatorId],
        target: student.coordinatorId,
        type: 'verification_reminder',
        relatedId: record.id,
        title: 'Document awaiting verification',
        message: `Review ${def.title} for ${student.displayName || 'your assigned intern'}.`,
      });
    }
  }
  return notices;
}

export async function remindStudent(db, ref, now = new Date()) {
  return db.runTransaction(async (tx) => {
    const [user, profile] = await tx.getAll(ref, db.collection('internship_profiles').doc(ref.id));
    const data = user.data();
    const receipts = db.collection('reminder_deliveries');
    const previous = await tx.get(receipts.where('studentId', '==', ref.id));
    const saved = new Map(previous.docs.map((d) => [d.id, d]));
    let notices = [];
    if (
      data?.role === 'student' &&
      data.active &&
      data.enrollmentStatus === 'active' &&
      !profile.get('archived')
    ) {
      const [defs, records, coordinator] = await Promise.all([
        tx.get(db.collection('requirement_definitions')),
        tx.get(db.collection('requirements').where('studentId', '==', ref.id)),
        data.coordinatorId ? tx.get(db.collection('users').doc(data.coordinatorId)) : null,
      ]);
      const rows = (snapshot) => snapshot.docs.map((doc) => ({ ...doc.data(), id: doc.id }));
      notices = remindersFor({
        student: { ...data, id: ref.id },
        profile: profile.data(),
        coordinator: coordinator?.data(),
        definitions: rows(defs),
        submissions: rows(records),
        now,
      });
    }
    const notifications = db.collection('notifications');
    const pending = previous.docs.filter((d) => d.get('scheduledFor').toMillis() > now.getTime());
    const snapshots = pending.length
      ? await tx.getAll(...pending.map((d) => notifications.doc(d.get('notificationId'))))
      : [];
    const existingNotices = new Set(snapshots.filter((d) => d.exists).map((d) => d.id));
    for (const n of notices) {
      const id = createHash('sha256').update(JSON.stringify(n.key)).digest('hex');
      const prior = saved.get(id);
      saved.delete(id);
      const scheduledFor = Timestamp.fromMillis(n.at);
      if (prior) {
        const oldTime = prior.get('scheduledFor').toMillis();
        if (oldTime <= now.getTime() || (oldTime === n.at && prior.get('message') === n.message))
          continue;
        // Admin deletion/deactivation is respected. Never recreate a removed notice.
        const notice = notifications.doc(prior.get('notificationId'));
        if (existingNotices.has(notice.id)) tx.update(notice, { scheduledFor, message: n.message });
        tx.update(prior.ref, { scheduledFor, message: n.message });
        continue;
      }
      const notice = notifications.doc();
      tx.create(notice, {
        title: n.title,
        message: n.message,
        type: n.type,
        relatedId: n.relatedId,
        targetRole: 'user:' + n.target,
        targetUserId: n.target,
        academicYear: data.academicYear,
        active: true,
        scheduledFor,
        read: false,
        readBy: [],
        dismissedBy: [],
        priority: 'normal',
        createdBy: 'system:reminders',
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.create(receipts.doc(id), {
        studentId: ref.id,
        notificationId: notice.id,
        scheduledFor,
        message: n.message,
      });
    }
    for (const prior of saved.values()) {
      if (prior.get('scheduledFor').toMillis() <= now.getTime()) continue;
      tx.delete(notifications.doc(prior.get('notificationId')));
      tx.delete(prior.ref);
    }
  });
}

export async function deliverReminders(db, now = new Date(), coordinatorId) {
  let students = db.collection('users').where('role', '==', 'student');
  if (coordinatorId) students = students.where('coordinatorId', '==', coordinatorId);
  students = students.orderBy(FieldPath.documentId()).limit(50);
  let cursor;
  for (;;) {
    const page = await (cursor ? students.startAfter(cursor) : students).get();
    for (let i = 0; i < page.size; i += 8) {
      await Promise.all(page.docs.slice(i, i + 8).map((student) => remindStudent(db, student.ref, now)));
    }
    if (page.size < 50) return;
    cursor = page.docs.at(-1);
  }
}
