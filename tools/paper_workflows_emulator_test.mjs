// A real local Auth/Firestore session, with an in-memory private object store.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { PDFDocument } from 'pdf-lib';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import {
  handleEvaluationAction,
  createStaffEvaluation,
  submitPublicEvaluation,
} from './evaluation_core.mjs';
import { mailboxProof } from './evaluation_test_mailbox.mjs';
import { finalizeRequirement } from './requirement_submission.mjs';
import { handleDtrAttendance } from './dtr_attendance_core.mjs';
import { creditedHours } from '../functions/attendance.mjs';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.SUPABASE_URL = 'http://storage.invalid';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fixture';
process.env.SUPABASE_ANON_KEY = 'fixture';
initializeApp({ projectId: 'demo-practicum-connect' });
const db = getFirestore(),
  auth = getAuth(),
  files = new Map();
const nativeFetch = globalThis.fetch;
globalThis.fetch = async (url, options = {}) => {
  if (!String(url).startsWith(process.env.SUPABASE_URL)) return nativeFetch(url, options);
  const route = new URL(url).pathname.replace('/storage/v1/object', '');
  if (route.startsWith('/upload/sign/'))
    return Response.json({ url: '/object' + route + '?token=fixture' });
  if (route.startsWith('/sign/'))
    return Response.json({ signedURL: '/object' + route + '?token=fixture' });
  if (options.method === 'POST') {
    files.set(route, options.body);
    return Response.json({});
  }
  const key = route.replace('/authenticated', '');
  return files.has(key)
    ? new Response(files.get(key), {
        headers: { 'Content-Type': key.endsWith('.jpg') ? 'image/jpeg' : 'application/pdf' },
      })
    : new Response(null, { status: 404 });
};
async function identity(role) {
  const email = randomUUID() + '@example.invalid',
    password = randomUUID();
  const { uid } = await auth.createUser({ email, password, emailVerified: true });
  if (role === 'student') await auth.setCustomUserClaims(uid, { student_enrolled: true });
  const login = await nativeFetch(
    'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  return { uid, authorization: 'Bearer ' + (await login.json()).idToken };
}
const staff = await identity('coordinator'),
  student = await identity('student');
const profile = {
  role: 'student',
  active: true,
  enrollmentStatus: 'active',
  coordinatorId: staff.uid,
  academicYear: '2026-2027',
  program: 'Science',
};
await db.doc('users/' + student.uid).set(profile);
await db
  .doc('users/' + staff.uid)
  .set({ role: 'coordinator', active: true, approvalStatus: 'approved' });
const doc = await PDFDocument.create();
const page = doc.addPage();
const field = doc.getForm().createTextField('Supervisor evaluation');
field.enableRequired();
field.addToPage(page);
const blank = await doc.save();
field.setText('Completed review');
const filled = await doc.save();
const templatePath = staff.uid + '/form_templates/official.pdf';
files.set('/PracticumConnectStorage/' + templatePath, blank);
const email = 'supervisor@example.invalid';
const created = await createStaffEvaluation({
  authorization: staff.authorization,
  body: {
    studentId: student.uid,
    templatePath,
    supervisorEmail: email,
    supervisorName: 'Supervisor',
    companyName: 'Company',
  },
});
assert.equal(created.status, 201, JSON.stringify(created));
const token = created.payload.token;
const proof = await mailboxProof(token, email);
const credentials = { token, email, proof };
assert.ok(
  (await handleEvaluationAction({ body: { ...credentials, action: 'officialPdf' } })).payload.url,
);
const { uploadId } = (await handleEvaluationAction({ body: { ...credentials, action: 'uploadPdf' } }))
  .payload;
const object = '/practicum-evaluations/' + token + '/' + uploadId + '.pdf';
const submit = () => submitPublicEvaluation({ body: { ...credentials, uploadId, confirmed: true } });
assert.equal((await submit()).status, 400);
files.set(object, Buffer.from('invalid PDF'));
assert.equal((await submit()).status, 400);
files.set(object, blank);
assert.equal((await submit()).status, 400);
files.set(object, filled);
assert.deepEqual((await Promise.all([submit(), submit()])).map((r) => r.status).sort(), [200, 409]);
const record = (await db.doc('supervisor_evaluations/' + token).get()).data();
assert.ok(record.completedHash);
const visible = (await db.doc('evaluation_status/' + record.statusId).get()).data();
assert.deepEqual(
  Object.keys(visible).sort(),
  ['academicYear', 'createdAt', 'status', 'studentId', 'submittedAt'].sort(),
);
assert.ok(
  (
    await handleEvaluationAction({
      authorization: staff.authorization,
      body: { action: 'staffPdf', token },
    })
  ).payload.url,
);
console.log(
  'PASS evaluation download, validation, final lock, staff retrieval and status-only visibility',
);

const definitionId = randomUUID();
await db
  .doc('requirement_definitions/' + definitionId)
  .set({ active: true, title: 'Report', program: 'Science' });
const req = {
  definitionId,
  storagePath: student.uid + '/requirements/1_report.pdf',
  fileName: 'report.pdf',
};
const finalize = (body) => finalizeRequirement({ authorization: student.authorization, body });
assert.equal((await finalize(req)).status, 400);
assert.equal(
  (await finalize({ ...req, storagePath: staff.uid + '/requirements/1_report.pdf' })).status,
  400,
);
files.set('/PracticumConnectStorage/' + req.storagePath, filled);
const first = await finalize(req);
assert.equal(first.status, 200, JSON.stringify(first));
const ref = db.doc('requirements/' + first.payload.id);
assert.equal((await ref.get()).get('title'), 'Report');
const reviewTime = Timestamp.fromMillis(1600000000000);
await ref.update({status:'needs_revision', remarks:'Update the final section.',reviewedBy:staff.uid,reviewedAt:reviewTime});
const original = (await ref.get()).data();
const revision = {
  ...req,
  requirementId: ref.id,
  expectedVersion: 1,
  storagePath: student.uid + '/requirements/2_report.pdf',
};
files.set('/PracticumConnectStorage/' + revision.storagePath, filled);
for (const result of await Promise.all([finalize(revision), finalize(revision)]))
  assert.equal(result.status, 200);
assert.equal((await ref.get()).get('version'), 2);
assert.equal(
  (await db.collection('requirement_versions').where('requirementId', '==', ref.id).get()).size,
  1,
);
const history = (await db.doc('requirement_versions/' + ref.id + '_1').get()).data();
for (const name of ['fileName','storagePath','submittedAt','status','remarks','reviewedBy','reviewedAt','version']) {
  assert.deepEqual(history[name], original[name]);
}
assert.equal((await ref.get()).get('reviewedBy'),null);
assert.equal((await ref.get()).get('reviewedAt'),null);
console.log('PASS document ownership, prior review snapshot, atomic revision and retry');

const prev = new Date();
prev.setUTCDate(prev.getUTCDate() - 1);
prev.setUTCHours(0, 0, 0, 0);
const shift = db.collection('dtr_entries').doc();
await shift.set({
  studentId: student.uid,
  coordinatorId: staff.uid,
  date: Timestamp.fromDate(prev),
  workDate: prev.toISOString().slice(0, 10),
  archived:false,
  scheduleTimeZone: 'UTC',
  timeIn: Timestamp.fromMillis(+prev + 8 * 3600000),
  scheduledEndAt: Timestamp.fromMillis(+prev + 17 * 3600000),
  academicYear: profile.academicYear,
  breakMinutes: 0,
  attendanceState: 'in_progress',
  status: 'pending',
});
const close = (actualTime) =>
  handleDtrAttendance({
    authorization: staff.authorization,
    body: { action: 'close_early', recordId: shift.id, reason: 'Verified with supervisor', actualTime },
  });
assert.equal((await close('')).status, 400);
assert.equal((await close('07:00')).status, 400);
assert.equal((await close('16:00')).status, 200);
const corrected = (await shift.get()).data();
assert.equal(creditedHours(corrected), 8);
assert.equal(corrected.status, 'pending');
assert.ok(corrected.exceptionAt.toMillis() > corrected.timeOut.toMillis());
console.log('PASS missed sign-out credits the original shift and retains the staff action time');

const restBase = 'http://127.0.0.1:8080/v1/projects/demo-practicum-connect/databases/(default)/documents/';
async function changeStatus(actor, path, status) {
  return nativeFetch(restBase + path + '?updateMask.fieldPaths=status', {
    method:'PATCH', headers:{Authorization:actor.authorization,'Content-Type':'application/json'},
    body:JSON.stringify({fields:{status:{stringValue:status}}})
  });
}
assert.equal((await changeStatus(student,shift.path,'verified')).status,403);
assert.equal((await changeStatus(staff,shift.path,'verified')).status,200);
await shift.update({status:'pending',timeOut:Timestamp.now()});
assert.equal((await changeStatus(staff,shift.path,'verified')).status,403);
assert.equal((await changeStatus(student,'requirements/'+randomUUID(),'pending')).status,403);
assert.equal((await changeStatus(student,'requirement_versions/'+randomUUID(),'pending')).status,403);
console.log('PASS Firestore permits valid staff approval and protects submission and version writes');

const zone = new Date().getUTCHours() >= 6 && new Date().getUTCHours() < 18 ? 'UTC' : 'Pacific/Fiji';
await db.doc('internship_profiles/'+student.uid).set({academicYear:profile.academicYear,shiftStartMinutes:0,
  shiftEndMinutes:1439,workDays:[1,2,3,4,5,6,7],timeZone:zone});
const photoPath=student.uid+'/dtr-checkins/fixture.jpg';
files.set('/PracticumConnectStorage/'+photoPath,Buffer.from([255,216,255]));
const clockIn=()=>handleDtrAttendance({authorization:student.authorization,body:{action:'clock_in',photoPath}});
await db.doc('users/'+student.uid).update({academicYear:''});
assert.equal((await clockIn()).status,409);
await db.doc('users/'+student.uid).update({academicYear:profile.academicYear});
assert.deepEqual((await Promise.all([clockIn(),clockIn()])).map(r=>r.status).sort(),[200,409]);
console.log('PASS attendance requires an assigned term and concurrent clock-ins yield one daily record');

const beforeRevision = await ref.get();
const staleRevision = {...revision, storagePath:student.uid+'/requirements/3_report.pdf'};
files.set('/PracticumConnectStorage/'+staleRevision.storagePath,filled);
assert.equal((await finalize(staleRevision)).status,409);
assert.ok((await ref.get()).updateTime.isEqual(beforeRevision.updateTime));
assert.equal((await db.collection('requirement_versions').where('requirementId','==',ref.id).get()).size,1);

// Archived legacy records can still carry their former active status.
await ref.update({archived:true,status:'needs_revision'});
const sealed = await ref.get();
assert.equal((await finalize({...staleRevision,expectedVersion:2})).status,403);
assert.ok((await ref.get()).updateTime.isEqual(sealed.updateTime));
await shift.update({archived:true,status:'needs_revision',attendanceState:'in_progress'});
const sealedShift = await shift.get();
assert.equal((await close('16:00')).status,409);
assert.equal((await handleDtrAttendance({authorization:student.authorization,body:{
  action:'revision_response', recordId:shift.id,response:'Confirmed by the supervisor.',
}})).status,409);
assert.ok((await shift.get()).updateTime.isEqual(sealedShift.updateTime));
console.log('PASS stale revision and trusted attendance/submission handlers preserve sealed records');
