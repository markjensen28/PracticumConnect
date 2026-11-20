import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { sendEvaluationMail, verifyPublicEvaluationAccess } from './evaluation_core.mjs';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.APP_ORIGIN = 'https://school.example.invalid';
const projectId = process.env.FIREBASE_PROJECT_ID || 'demo-enrollment';
assert.ok(projectId.startsWith('demo-'));
initializeApp({ projectId });
const db = getFirestore(),
  auth = getAuth();
const token = randomBytes(24).toString('base64url');
const email = token + '@example.invalid',
  password = randomBytes(16).toString('hex');
const coordinator = await auth.createUser({ email, password });
await db
  .doc('users/' + coordinator.uid)
  .set({ role: 'coordinator', active: true, approvalStatus: 'approved' });
const login = await fetch(
  'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator',
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  },
);
const authorization = 'Bearer ' + (await login.json()).idToken;
const studentRef = db.doc('users/test-' + token);
const supervisorEmail = 'supervisor@example.invalid';
await db
  .doc('supervisor_evaluations/' + token)
  .set({
    studentId: studentRef.id,
    coordinatorId: coordinator.uid,
    studentName: 'Test Student',
    supervisorEmail,
    status: 'pending',
    expiresAt: Timestamp.fromMillis(Date.now() + 600000),
  });
const sent = [];
const send = (action, params = {}) =>
  sendEvaluationMail({ authorization, body: { token, action, ...params } }, async (mail) => sent.push(mail));
await studentRef.set({ role: 'student', coordinatorId: 'other' });
assert.equal((await send('invite')).status, 403);
await studentRef.update({ coordinatorId: coordinator.uid });
assert.equal((await send('invite', { email: 'different@example.invalid' })).status, 200);
assert.equal(sent[0].to, supervisorEmail);
assert.ok(sent[0].text.includes('https://school.example.invalid/?evaluation=' + token));
assert.equal((await send('requestCode', { email: supervisorEmail })).status, 200);
assert.equal((await send('requestCode', { email: supervisorEmail })).status, 429);
const verify = (code) => verifyPublicEvaluationAccess({ body: { token, email: supervisorEmail, code } });
const code = sent[1].text.match(/code is ([A-F0-9]{12})/)[1];
for (let i = 0; i < 5; i++) assert.equal((await verify('wrong')).status, 403);
assert.equal((await verify(code)).status, 403);
await db.doc('evaluation_mailboxes/' + token).update({ attempts: 0, codeUntil: Date.now() - 1 });
assert.equal((await verify(code)).status, 403);
console.log(
  'PASS: assigned staff invitations, server-selected recipient, resend cooldown, attempt limit and code expiry.',
);
