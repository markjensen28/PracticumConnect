import {creditedHours} from './attendance.mjs';
import { FieldValue } from 'firebase-admin/firestore';

export function calculateStage({ profile, definitions, requirements, shifts, evaluations }) {
  const latest = new Map();
  const byTitle = new Map();
  // Match the current submission for each definition, including older title-only records.
  for (const requirement of requirements.sort(
    (a, b) => (b.submittedAt?.toMillis?.() ?? 0) - (a.submittedAt?.toMillis?.() ?? 0),
  )) {
    const map = requirement.definitionId ? latest : byTitle;
    const key = requirement.definitionId || requirement.title?.trim().toLowerCase();
    if (!map.has(key)) map.set(key, requirement);
  }
  function record(definition) {
    const named = byTitle.get(definition.title?.trim().toLowerCase());
    const exact = latest.get(definition.id);
    if (!named || !exact) return exact || named;
    return named.submittedAt?.toMillis() > exact.submittedAt?.toMillis() ? named : exact;
  }
  const label = (d) => `${d.category || ''} ${d.title || ''}`;
  const completion = definitions.filter((d) =>
    /performance|evaluation|final report|narrative|exit form/i.test(label(d)),
  );
  const deployment = definitions.filter(
    (d) => !completion.includes(d) && !/weekly|dtr|daily time|monitoring/i.test(label(d)),
  );
  const prerequisites = deployment.length ? deployment : definitions;
  if (!prerequisites.length || !prerequisites.every((d) => record(d))) return 'Pending Requirements';
  const verified = (d) => record(d)?.status === 'verified';
  if (!prerequisites.every(verified)) return 'For Verification';
  if (!/confirm|deploy|ongoing|active/i.test(profile.placementStatus || '')) return 'Ready for Deployment';
  const hours = shifts.reduce((total, shift) => {
    return total + (shift.status === 'verified' ? creditedHours(shift) : 0);
  }, 0);
  return hours >= (profile.requiredHours ?? 400) &&
    evaluations.some((e) => e.status === 'submitted') &&
    completion.every(verified)
    ? 'Completed'
    : 'Ongoing Internship';
}

export async function reconcileStudent(db, uid) {
  return db.runTransaction(async (tx) => {
    const userRef = db.collection('users').doc(uid);
    const profileRef = db.collection('internship_profiles').doc(uid);
    const [userDoc, profileDoc] = await tx.getAll(userRef, profileRef);
    const user = userDoc.data();
    const profile = profileDoc.data() || {};
    if (user?.role !== 'student' || profile.archived) return;
    const year = (user.academicYear || profile.academicYear || '').trim();
    if (!year) return;
    const studentQuery = (name) => db.collection(name).where('studentId', '==', uid);
    const [defs, requirements, shifts, evaluations] = await Promise.all(
      [
        db.collection('requirement_definitions'),
        studentQuery('requirements'),
        studentQuery('dtr_entries'),
        studentQuery('supervisor_evaluations'),
      ].map((query) => tx.get(query)),
    );
    const current = (snapshot) =>
      snapshot.docs.map((doc) => doc.data()).filter((d) => !d.archived && d.academicYear === year);
    const definitions = defs.docs
      .map((doc) => ({ ...doc.data(), id: doc.id }))
      .filter(
        (d) =>
          d.active !== false && (!d.program || d.program === 'All Programs' || d.program === user.program),
      );
    const status = calculateStage({
      profile,
      definitions,
      requirements: current(requirements),
      shifts: current(shifts),
      evaluations: current(evaluations),
    });
    const coordinatorId = user.coordinatorId ?? profile.coordinatorId ?? null;
    if (
      profile.status === status &&
      profile.academicYear === year &&
      profile.coordinatorId === coordinatorId &&
      (status !== 'Completed' || profile.completedAt)
    )
      return;
    tx.set(
      profileRef,
      {
        status,
        academicYear: year,
        coordinatorId,
        archived: false,
        ...(status === 'Completed' && !profile.completedAt && { completedAt: FieldValue.serverTimestamp() }),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}
