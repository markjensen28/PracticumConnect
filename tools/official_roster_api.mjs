import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { ensureAdminApp } from './staff_claims_core.mjs';
import { studentEmailConfigured } from './school_email.mjs';
import { managePendingStudent, planRoster, provisionStudent } from './student_enrollment_core.mjs';

const rosterNumberKey = (number) => String(number || '').trim().normalize('NFKC').toUpperCase();

export function validRosterOrigin(value, localServer = false) {
  try {
    const url = new URL(value);
    if (url.username || url.password) return false;
    return url.protocol === 'https:' || (localServer && url.protocol === 'http:' &&
      ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname));
  } catch {
    return false;
  }
}

export async function importOfficialRoster({ authorization, body, requesterIp }, localServer = false) {
  ensureAdminApp();
  const auth = getAuth(),
    db = getFirestore();
  let identity;
  try {
    identity = await auth.verifyIdToken(/^Bearer (\S+)$/i.exec(authorization || '')?.[1] || '', true);
  } catch {
    return { status: 401, payload: { error: 'Administrator sign-in required.' } };
  }
  const actor = (await db.collection('users').doc(identity.uid).get()).data();
  if (!actor?.active || actor.role !== 'admin')
    return { status: 403, payload: { error: 'Only the college administrator can import the roster.' } };
  const action = body?.action;
  const rosterAction = action === 'preview' || action === 'import';
  const pendingAction = action === 'resend' || action === 'remove';
  if (
    (!rosterAction && !pendingAction) ||
    (rosterAction && (!Array.isArray(body?.rows) || body.rows.length > 100 ||
      (action === 'import' && body.rows.length !== 1))) ||
    (pendingAction && (typeof body?.studentNumber !== 'string' || !rosterNumberKey(body.studentNumber)))
  )
    return {
      status: 400,
      payload: { error: 'Choose a valid roster action and provide its required student data.' },
    };
  try {
    if (pendingAction) {
      if (action === 'resend') {
        if (
          !studentEmailConfigured() ||
          !validRosterOrigin(process.env.APP_ORIGIN, localServer)
        )
          return {
            status: 503,
            payload: { error: 'Configure the public school app URL and server email delivery before resending.' },
          };
      }
      const result = await managePendingStudent(db, auth, body.studentNumber, action, { requesterIp });
      return { status: 200, payload: { ok: true, ...result } };
    }
    const plan = await planRoster(db, auth, body.rows);
    if (body.action === 'preview')
      return { status: 200, payload: { rows: plan.length, legacy: plan.filter((r) => r.legacy).length } };
    if (plan[0].legacy)
      return {
        status: 409,
        payload: { error: 'Existing accounts require the reviewed administrator migration command.' },
      };
    if (
      !studentEmailConfigured() ||
      !validRosterOrigin(process.env.APP_ORIGIN, localServer)
    ) {
      return {
        status: 503,
        payload: { error: 'Configure the public school app URL and server email delivery before importing.' },
      };
    }
    const invitation = await provisionStudent(db, auth, plan[0], { requesterIp });
    return { status: 200, payload: { ok: true, invitation } };
  } catch (error) {
    return { status: 400, payload: { error: error.message || 'Roster import failed.' } };
  }
}
