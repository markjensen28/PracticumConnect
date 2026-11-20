import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { ensureAdminApp } from '../tools/staff_claims_core.mjs';
import { activateStudent } from '../tools/student_enrollment_core.mjs';

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).end();
  try {
    ensureAdminApp();
    const result = await activateStudent(getFirestore(), getAuth(), req.headers.authorization);
    return res.status(result.status).json(result.payload);
  } catch {
    return res.status(503).json({ error: 'Activation is temporarily unavailable. Sign in again to retry.' });
  }
}
