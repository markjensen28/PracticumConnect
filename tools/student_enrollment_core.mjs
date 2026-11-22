import { createHash, randomBytes } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { sendStudentInvitation, singleMailbox } from './school_email.mjs';

const digest = (text) => createHash('sha256').update(text).digest('hex');
const numberKey = (number) =>
  String(number || '')
    .trim()
    .normalize('NFKC')
    .toUpperCase();
const emailKey = (email) =>
  String(email || '')
    .trim()
    .toLowerCase();

export function normalizeRoster(rows) {
  if (!Array.isArray(rows) || !rows.length) throw new Error('Provide a nonempty JSON array of roster rows.');
  const numbers = new Set(),
    emails = new Set();
  return rows.map((row, i) => {
    if (typeof row?.studentNumber !== 'string')
      throw new Error(`Row ${i + 1}: studentNumber must be text (preserve leading zeros).`);
    const studentNumber = numberKey(row.studentNumber),
      email = emailKey(row.email);
    const displayName = String(row.displayName || '').trim();
    if (
      !studentNumber ||
      typeof row.displayName !== 'string' ||
      !displayName ||
      typeof row.email !== 'string' ||
      !singleMailbox(email) ||
      numbers.has(studentNumber) ||
      emails.has(email)
    )
      throw new Error(`Invalid or duplicate identity on row ${i + 1}.`);
    numbers.add(studentNumber);
    emails.add(email);
    const academics = {};
    for (const field of ['academicYear', 'program', 'section', 'department']) {
      if (row[field] != null && typeof row[field] !== 'string')
        throw new Error(`Row ${i + 1}: ${field} must be text.`);
      if (row[field]?.trim()) academics[field] = row[field].trim();
    }
    return { studentNumber, email, displayName, academics };
  });
}

// Preflight the full list before the first write, including legacy numbers
// with case/spacing differences. Matching legacy records keep their UID.
export async function planRoster(db, auth, rows) {
  const students = (await db.collection('users').where('role', '==', 'student').get()).docs;
  const plan = [];
  for (const row of normalizeRoster(rows)) {
    const legacy = students.filter(
      (doc) =>
        numberKey(doc.data().studentNumber) === row.studentNumber || emailKey(doc.data().email) === row.email,
    );
    const existing = legacy[0];
    if (
      legacy.length > 1 ||
      (existing &&
        (numberKey(existing.data().studentNumber) !== row.studentNumber ||
          emailKey(existing.data().email) !== row.email))
    )
      throw new Error(`Resolve conflicting records for ${row.studentNumber}.`);
    const rosterRef = db.collection('student_roster').doc(digest(row.studentNumber));
    const reserved = (await rosterRef.get()).data();
    const uid = existing?.id || reserved?.uid || 'roster-' + digest(row.studentNumber);
    let account;
    try {
      account = await auth.getUserByEmail(row.email);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
    if (
      account?.disabled ||
      (existing &&
        !reserved &&
        account?.customClaims?.app_role &&
        account.customClaims.app_role !== 'student') ||
      (account && account.uid !== uid) ||
      (existing && !account && !reserved) ||
      (reserved && (reserved.email !== row.email || reserved.uid !== uid)) ||
      (existing?.data().active === false && !reserved)
    )
      throw new Error(`Review account conflict for ${row.studentNumber}.`);
    plan.push({ ...row, uid, rosterRef, legacy: !!existing && !reserved });
  }
  return plan;
}

export async function provisionStudent(
  db, auth, row, { resend = false, deliver = sendStudentInvitation, requesterIp } = {},
) {
  const { uid, email, studentNumber, displayName, rosterRef } = row;
  const userRef = db.collection('users').doc(uid);
  const emailRef = db.collection('roster_emails').doc(digest(email));
  const lease = randomBytes(16).toString('hex');
  const mode = await db.runTransaction(async (tx) => {
    const [roster, emailDoc, user] = await tx.getAll(rosterRef, emailRef, userRef);
    const saved = roster.data();
    if (
      (saved && (saved.uid !== uid || saved.email !== email)) ||
      (emailDoc.exists && emailDoc.data().uid !== uid) ||
      (user.exists &&
        (user.data().role !== 'student' ||
          emailKey(user.data().email) !== email ||
          numberKey(user.data().studentNumber) !== studentNumber))
    )
      throw new Error('Roster identity conflict.');
    if (saved?.status === 'active') return 'already_active';
    if (saved?.leaseUntil > Date.now()) throw new Error('An import is already processing this row.');
    if (saved?.invitedAt && !resend) return 'already_invited';
    tx.set(emailRef, { uid });
    tx.set(rosterRef, { uid, email, studentNumber, lease, leaseUntil: Date.now() + 600000 }, { merge: true });
    if (saved?.status === 'pending') return 'send';
    tx.set(
      userRef,
      {
        ...row.academics,
        uid,
        email,
        studentNumber,
        displayName,
        role: 'student',
        active: false,
        enrollmentStatus: 'provisioning',
        approvalStatus: 'pending',
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return 'prepare';
  });
  if (mode === 'already_active' || mode === 'already_invited') return mode;
  try {
    if (mode === 'prepare') {
      const password = randomBytes(48).toString('base64url');
      try {
        const existing = await auth.getUser(uid);
        if (existing.disabled || emailKey(existing.email) !== email)
          throw new Error('Authentication identity conflict.');
        await auth.updateUser(uid, { password, emailVerified: false });
        await auth.revokeRefreshTokens(uid);
      } catch (e) {
        if (e.code !== 'auth/user-not-found') throw e;
        await auth.createUser({ uid, email, password, displayName, emailVerified: false });
      }
      await db.runTransaction(async (tx) => {
        if ((await tx.get(rosterRef)).data()?.lease !== lease) throw new Error('Import lease expired.');
        tx.update(rosterRef, { status: 'pending' });
        tx.update(userRef, { enrollmentStatus: 'pending' });
      });
    }
    await deliver({ to: email, displayName, auth, requesterIp });
    await rosterRef.update({ invitedAt: FieldValue.serverTimestamp() });
    return 'sent';
  } finally {
    await db.runTransaction(async (tx) => {
      if ((await tx.get(rosterRef)).data()?.lease === lease)
        tx.update(rosterRef, { lease: FieldValue.delete(), leaseUntil: FieldValue.delete() });
    });
  }
}

export async function managePendingStudent(db, auth, studentNumber, action, { requesterIp } = {}) {
  const normalizedNumber = numberKey(studentNumber);
  if (!normalizedNumber) throw new Error('Student number is required.');
  if (!['resend', 'remove'].includes(action)) throw new Error('Unsupported pending student action.');

  const rosterRef = db.collection('student_roster').doc(digest(normalizedNumber));
  const initialRoster = (await rosterRef.get()).data();
  if (!initialRoster?.uid || numberKey(initialRoster.studentNumber) !== normalizedNumber)
    throw new Error('No roster invitation was found for that student number.');

  const userRef = db.collection('users').doc(initialRoster.uid);
  const user = (await userRef.get()).data();

  if (action === 'resend') {
    if (
      !user ||
      user.role !== 'student' ||
      user.enrollmentStatus !== 'pending' ||
      user.active === true ||
      String(user.email || '').trim().toLowerCase() !== String(initialRoster.email || '').trim().toLowerCase()
    )
      throw new Error('Only a pending, unactivated student account can receive another invitation.');
    await provisionStudent(
      db,
      auth,
      {
        uid: initialRoster.uid,
        email: initialRoster.email,
        studentNumber: normalizedNumber,
        displayName: user.displayName || 'Student',
        academics: {
          academicYear: user.academicYear,
          program: user.program,
          section: user.section,
          department: user.department,
        },
        rosterRef,
      },
      { resend: true, requesterIp },
    );
    return { resent: true };
  }

  const lease = randomBytes(16).toString('hex');
  const emailRef = db.collection('roster_emails').doc(digest(String(initialRoster.email).trim().toLowerCase()));
  const locked = await db.runTransaction(async (tx) => {
    const [rosterSnapshot, userSnapshot, emailSnapshot] = await tx.getAll(rosterRef, userRef, emailRef);
    const roster = rosterSnapshot.data();
    const currentUser = userSnapshot.data();
    const isPending =
      roster?.status === 'pending' &&
      currentUser?.role === 'student' &&
      currentUser?.enrollmentStatus === 'pending' &&
      currentUser?.active !== true;
    const isInterruptedRemoval =
      roster?.status === 'removing' &&
      (!userSnapshot.exists ||
        (currentUser?.role === 'student' &&
          currentUser?.enrollmentStatus === 'pending' &&
          currentUser?.active !== true));
    if (
      !roster ||
      roster.uid !== initialRoster.uid ||
      (!isPending && !isInterruptedRemoval) ||
      (emailSnapshot.exists && emailSnapshot.data().uid !== initialRoster.uid)
    )
      throw new Error('This account is no longer pending and cannot be removed here.');
    if (roster.leaseUntil > Date.now()) throw new Error('This invitation is being processed. Try again shortly.');
    tx.update(rosterRef, {
      status: 'removing',
      lease,
      leaseUntil: Date.now() + 600000,
    });
    return true;
  });

  if (!locked) return { removed: false };
  let authDeleted = false;
  try {
    try {
      await auth.deleteUser(initialRoster.uid);
      authDeleted = true;
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      authDeleted = true;
    }
    await db.runTransaction(async (tx) => {
      const rosterSnapshot = await tx.get(rosterRef);
      const roster = rosterSnapshot.data();
      if (roster?.status !== 'removing' || roster.lease !== lease)
        throw new Error('Removal could not be confirmed. Refresh and check the student record.');
      tx.delete(userRef);
      tx.delete(rosterRef);
      tx.delete(emailRef);
    });
    return { removed: true };
  } catch (error) {
    if (!authDeleted) {
      await db.runTransaction(async (tx) => {
        const snapshot = await tx.get(rosterRef);
        const roster = snapshot.data();
        if (roster?.status === 'removing' && roster.lease === lease) {
          tx.update(rosterRef, {
            status: 'pending',
            lease: FieldValue.delete(),
            leaseUntil: FieldValue.delete(),
          });
        }
      }).catch(() => {});
    }
    throw error;
  }
}

export async function activateStudent(db, auth, authorization) {
  const token = /^Bearer (\S+)$/i.exec(authorization || '')?.[1];
  let identity;
  try {
    identity = await auth.verifyIdToken(token || '', true);
  } catch {
    return { status: 401, payload: { error: 'Sign in again.' } };
  }
  if (identity.email_verified !== true)
    return { status: 403, payload: { error: 'Verify your school email first.' } };
  const userRef = db.collection('users').doc(identity.uid);
  const allowed = await db.runTransaction(async (tx) => {
    const user = (await tx.get(userRef)).data();
    if (user?.role !== 'student' || !user.studentNumber) return false;
    const rosterRef = db.collection('student_roster').doc(digest(numberKey(user.studentNumber)));
    const row = (await tx.get(rosterRef)).data();
    if (
      row?.uid !== identity.uid ||
      row.email !== emailKey(identity.email) ||
      row.email !== emailKey(user.email)
    )
      return false;
    if (row.status === 'active') return user.active === true && user.enrollmentStatus === 'active';
    if (row.status !== 'pending' || user.enrollmentStatus !== 'pending') return false;
    tx.update(rosterRef, { status: 'active', activatedAt: FieldValue.serverTimestamp() });
    tx.update(userRef, {
      enrollmentStatus: 'active',
      approvalStatus: 'approved',
      active: true,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!allowed) return { status: 403, payload: { error: 'Ask your school to verify your roster entry.' } };
  const account = await auth.getUser(identity.uid);
  await auth.setCustomUserClaims(identity.uid, {
    ...account.customClaims,
    role: 'authenticated',
    app_role: 'student',
    student_enrolled: true,
  });
  return { status: 200, payload: { active: true } };
}
