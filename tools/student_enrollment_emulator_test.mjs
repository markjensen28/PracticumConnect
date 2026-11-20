import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import {
  normalizeRoster,
  planRoster,
  provisionStudent,
  activateStudent,
} from './student_enrollment_core.mjs';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
initializeApp({ projectId: 'demo-enrollment' });
const db = getFirestore(),
  auth = getAuth();
const id = randomUUID(),
  email = `student-${id}@example.invalid`;
const row = { email, studentNumber: id, displayName: 'Test Student' };
assert.throws(() =>
  normalizeRoster([row, { ...row, studentNumber: id.toUpperCase(), email: 'different@example.invalid' }]),
);
const [plan] = await planRoster(db, auth, [row]);
let mail;
const deliver = async (message) => {
  mail = message;
};
await provisionStudent(db, auth, plan, { deliver });
const profile = db.collection('users').doc(plan.uid);
assert.equal((await profile.get()).get('active'), false);
assert.equal((await auth.getUser(plan.uid)).emailVerified, false);
const resetLink = mail.text.match(/https?:\/\/\S+$/)[0];
const oobCode = new URL(resetLink).searchParams.get('oobCode');
const password = randomUUID();
async function identityRequest(action, body) {
  const response = await fetch(
    'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:' + action + '?key=emulator',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    },
  );
  const data = await response.json();
  assert.ok(response.ok, data.error?.message);
  return data;
}
await identityRequest('resetPassword', { oobCode, newPassword: password });
let login = await identityRequest('signInWithPassword', { email, password, returnSecureToken: true });
if (!(await auth.getUser(plan.uid)).emailVerified) {
  assert.equal((await activateStudent(db, auth, 'Bearer ' + login.idToken)).status, 403);
  const verifyLink = await auth.generateEmailVerificationLink(email);
  await identityRequest('update', { oobCode: new URL(verifyLink).searchParams.get('oobCode') });
  login = await identityRequest('signInWithPassword', { email, password, returnSecureToken: true });
}
assert.equal((await activateStudent(db, auth, 'Bearer ' + login.idToken)).status, 200);
assert.equal((await profile.get()).get('enrollmentStatus'), 'active');
assert.equal((await auth.getUser(plan.uid)).customClaims.student_enrolled, true);
let sends = 0;
await provisionStudent(db, auth, plan, {
  deliver: async () => {
    sends++;
  },
});
assert.equal(sends, 0);
await assert.rejects(planRoster(db, auth, [{ ...row, email: 'conflicting@example.invalid' }]));
console.log(
  'PASS: pending creation, mailbox activation, Firebase claims, duplicate reservation, retry and conflicting identity.',
);
const legacyId = 'legacy-' + randomUUID();
const legacyRow = {displayName:'Legacy Student',email:legacyId+'@example.invalid',studentNumber:legacyId};
const legacyAccount = await auth.createUser({email:legacyRow.email,password:randomUUID(),emailVerified:true});
const legacyProfile = db.doc('users/'+legacyAccount.uid);
await legacyProfile.set({...legacyRow,role:'student',active:true,coordinatorId:'existing-assignment'});
const [legacyPlan] = await planRoster(db,auth,[legacyRow]);
assert.equal(legacyPlan.legacy,true);
assert.equal(legacyPlan.uid,legacyAccount.uid);
await assert.rejects(provisionStudent(db,auth,legacyPlan,{deliver:async()=>{throw Error('test mail failure');}}));
assert.equal((await legacyProfile.get()).get('active'),false);
const [retry] = await planRoster(db,auth,[legacyRow]);
await provisionStudent(db,auth,retry,{deliver});
assert.equal((await legacyProfile.get()).get('coordinatorId'),'existing-assignment');
assert.equal((await auth.getUser(legacyAccount.uid)).emailVerified,false);
assert.equal((await legacyProfile.get()).get('enrollmentStatus'),'pending');
console.log('PASS: legacy migration preserves UID and assignment; failed delivery is retryable.');

const {importOfficialRoster} = await import('./official_roster_api.mjs');
assert.equal((await importOfficialRoster({authorization:'Bearer '+login.idToken,body:{action:'preview',rows:[row]}})).status,403);
console.log('PASS: students cannot import the school roster.');
