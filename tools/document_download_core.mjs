import './trusted_certificates.mjs';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { ensureAdminApp } from './staff_claims_core.mjs';

export function canReadDocument(actorId, actor, owner, path) {
  if (actor?.active !== true) return false;
  const [ownerId, folder] = path.split('/');
  if (actor.role === 'admin') return true;
  if (actor.role === 'coordinator' && actor.approvalStatus !== 'approved') return false;
  if (!['student', 'coordinator'].includes(actor.role)) return false;
  if (actorId === ownerId || folder === 'form_templates') return true;
  return actor.role === 'coordinator' && owner?.role === 'student' &&
    owner.coordinatorId === actorId && ['requirements', 'dtr-checkins'].includes(folder);
}

export async function createDocumentDownload({ authorization, body }, dependencies = {}) {
  try {
    const token = /^Bearer (\S+)$/i.exec(authorization || '')?.[1];
    if (!token) return { status: 401, payload: { error: 'Sign-in is required.' } };
    let input;
    try { input = typeof body === 'string' ? JSON.parse(body) : body; }
    catch { return { status: 400, payload: { error: 'Invalid JSON.' } }; }
    const path = input?.path;
    if (typeof path !== 'string' || path.length > 1024 ||
        path.split('/').length !== 3 || path.split('/').some(p => !p || p === '.' || p === '..') ||
        /[%\\\x00-\x1f]/.test(path)) {
      return { status: 400, payload: { error: 'Invalid storage path.' } };
    }
    if (!dependencies.auth) ensureAdminApp();
    const auth = dependencies.auth || getAuth();
    const db = dependencies.db || getFirestore();
    let decoded;
    try { decoded = await auth.verifyIdToken(token, true); }
    catch { return { status: 401, payload: { error: 'Sign in again.' } }; }
    const ownerId = path.split('/')[0];
    const [actorDoc, ownerDoc] = await Promise.all([
      db.collection('users').doc(decoded.uid).get(),
      db.collection('users').doc(ownerId).get(),
    ]);
    if (actorDoc.data()?.role === 'student' && (actorDoc.data().enrollmentStatus !== 'active' || !decoded.student_enrolled || !decoded.email_verified)) {
      return { status: 403, payload: { error: 'Activate your roster account first.' } };
    }
    if (!canReadDocument(decoded.uid, actorDoc.data(), ownerDoc.data(), path)) {
      return { status: 403, payload: { error: 'This document is not assigned to your account.' } };
    }
    const config = dependencies.config || process.env;
    const base = config.SUPABASE_URL?.replace(/\/$/, '');
    const key = config.SUPABASE_SERVICE_ROLE_KEY;
    if (!base || !key) return { status: 503, payload: { error: 'Document signing is not configured on the server.' } };
    const bucket = config.SUPABASE_BUCKET || 'PracticumConnectStorage';
    const response = await (dependencies.fetch || fetch)(
      `${base}/storage/v1/object/sign/${encodeURIComponent(bucket)}/${path.split('/').map(encodeURIComponent).join('/')}`,
      { method: 'POST', headers: { Authorization: `Bearer ${key}`, apikey: key, 'Content-Type': 'application/json' },
        body: JSON.stringify({ expiresIn: 300 }) },
    );
    if (!response.ok) return { status: 502, payload: { error: 'Unable to open the stored document.' } };
    const result = await response.json();
    if (typeof result.signedURL !== 'string') throw new Error('Missing signed URL');
    return { status: 200, payload: { url: new URL(`${base}/storage/v1${result.signedURL}`).toString() } };
  } catch {
    return { status: 500, payload: { error: 'Document access could not be verified.' } };
  }
}
