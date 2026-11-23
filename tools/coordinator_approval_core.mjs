import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { canonicalCasProgram, casCollegeName, coordinatorProgram } from './cas_programs.mjs';

function ensureAdminApp() {
  if (getApps().length > 0) return getApps()[0];

  const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (serviceAccountJson) {
    const serviceAccount = JSON.parse(serviceAccountJson);
    return initializeApp({
      credential: cert(serviceAccount),
      projectId: serviceAccount.project_id,
    });
  }

  const projectId = process.env.FIREBASE_PROJECT_ID?.trim();
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');

  if (projectId && clientEmail && privateKey) {
    return initializeApp({
      credential: cert({ projectId, clientEmail, privateKey }),
      projectId,
    });
  }

  // Local development can use GOOGLE_APPLICATION_CREDENTIALS, which the
  // Firebase Admin SDK reads through applicationDefault().
  return initializeApp({
    credential: applicationDefault(),
    projectId: projectId || undefined,
  });
}

function bearerToken(authorization) {
  if (!authorization || typeof authorization !== 'string') return null;
  const [scheme, token] = authorization.split(' ');
  return scheme?.toLowerCase() === 'bearer' && token ? token : null;
}

function parseBody(body) {
  if (body && typeof body === 'object') return body;
  if (typeof body === 'string' && body.trim()) return JSON.parse(body);
  return {};
}

export async function reviewCoordinatorRequest({ authorization, body }, dependencies = {}) {
  const token = bearerToken(authorization);
  if (!token) {
    return { status: 401, payload: { error: 'Administrator sign-in is required.' } };
  }

  if (!dependencies.auth || !dependencies.db) ensureAdminApp();
  const auth = dependencies.auth || getAuth();
  const db = dependencies.db || getFirestore();
  const decoded = await auth.verifyIdToken(token, true);
  const adminSnapshot = await db.collection('users').doc(decoded.uid).get();
  const adminProfile = adminSnapshot.data();

  if (
    !adminSnapshot.exists ||
    adminProfile?.role !== 'admin' ||
    adminProfile?.active !== true
  ) {
    return {
      status: 403,
      payload: { error: 'Only an active Practicum Connect administrator can review coordinator requests.' },
    };
  }

  const parsed = parseBody(body);
  const uid = String(parsed.uid || '').trim();
  const action = String(parsed.action || '').trim().toLowerCase();
  if (!uid || uid.includes('/') || !['approve', 'reject', 'set-program'].includes(action)) {
    return {
      status: 400,
      payload: { error: 'A coordinator account and a valid action are required.' },
    };
  }

  const targetRef = db.collection('users').doc(uid);
  const targetSnapshot = await targetRef.get();
  const target = targetSnapshot.data();
  if (!targetSnapshot.exists || target?.role !== 'coordinator') {
    return { status: 404, payload: { error: 'Coordinator registration request was not found.' } };
  }
  if (action === 'set-program') {
    const program = canonicalCasProgram(parsed.program);
    if (!program) return { status: 400, payload: { error: 'Select one of the four CAS programs.' } };
    return db.runTransaction(async transaction => {
      const current = (await transaction.get(targetRef)).data();
      if (current?.role !== 'coordinator' || current.approvalStatus !== 'approved') {
        return { status: 409, payload: { error: 'Only approved coordinator accounts can change programs.' } };
      }
      const students = await transaction.get(db.collection('users').where('coordinatorId', '==', uid));
      if (students.docs.some(doc => {
        const student = doc.data();
        return student.role === 'student' && canonicalCasProgram(student.program) !== program;
      })) {
        return { status: 409, payload: {
          error: 'Reassign or remove students with a different or missing program before saving this coordinator’s program.',
        } };
      }
      transaction.update(targetRef, {
        program,
        department: casCollegeName,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { status: 200, payload: { ok: true, action, uid, program } };
    });
  }

  if (target?.approvalStatus !== 'pending') {
    return {
      status: 409,
      payload: { error: `This coordinator request is already ${target?.approvalStatus || 'processed'}.` },
    };
  }

  const program = parsed.program == null ? coordinatorProgram(target) : canonicalCasProgram(parsed.program);
  if (action === 'approve' && !program) {
    return { status: 400, payload: { error: 'Select a CAS program before approving this coordinator.' } };
  }

  const targetAuth = await auth.getUser(uid);
  const currentClaims = { ...(targetAuth.customClaims || {}) };

  if (action === 'approve') {
    await auth.setCustomUserClaims(uid, {
      ...currentClaims,
      app_role: 'coordinator',
      role: 'authenticated',
    });
    await targetRef.update({
      approvalStatus: 'approved',
      active: true,
      program,
      department: casCollegeName,
      approvedBy: decoded.uid,
      approvedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } else {
    delete currentClaims.app_role;
    delete currentClaims.role;
    await auth.setCustomUserClaims(uid, currentClaims);
    await targetRef.update({
      approvalStatus: 'rejected',
      active: false,
      rejectedBy: decoded.uid,
      rejectedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  await auth.revokeRefreshTokens(uid);

  return {
    status: 200,
    payload: {
      ok: true,
      action,
      uid,
      message:
        action === 'approve'
          ? 'Coordinator account approved and security claims applied.'
          : 'Coordinator registration request rejected.',
    },
  };
}
