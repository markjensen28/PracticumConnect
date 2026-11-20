import {creditedHours} from '../functions/attendance.mjs';
import { checkPdf, documentBucket, evaluationBucket, invalid, readStoredFile, signedFileUrl, storageRequest } from './private_files.mjs';
import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { sendSchoolEmail, singleMailbox } from './school_email.mjs';
import { createHash, randomBytes } from 'node:crypto';

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

  return initializeApp({
    credential: applicationDefault(),
    projectId: projectId || undefined,
  });
}


function isCompletionDefinition(data) {
  const key = `${data.category || ''} ${data.title || ''}`.toLowerCase();
  return key.includes('performance') ||
    key.includes('evaluation') ||
    key.includes('final report') ||
    key.includes('narrative') ||
    key.includes('exit form');
}

function isOngoingDefinition(data) {
  const key = `${data.category || ''} ${data.title || ''}`.toLowerCase();
  return key.includes('weekly') ||
    key.includes('dtr') ||
    key.includes('daily time') ||
    key.includes('monitoring');
}

async function syncCompletionStage(db, studentId, submittedAcademicYear) {
  if (!studentId) return;
  const [userDoc, profileDoc, definitionsSnapshot, requirementsSnapshot, dtrSnapshot] =
    await Promise.all([
      db.collection('users').doc(studentId).get(),
      db.collection('internship_profiles').doc(studentId).get(),
      db.collection('requirement_definitions').get(),
      db.collection('requirements').where('studentId', '==', studentId).get(),
      db.collection('dtr_entries').where('studentId', '==', studentId).get(),
    ]);

  if (!userDoc.exists || !profileDoc.exists) return;
  const user = userDoc.data() || {};
  const profile = profileDoc.data() || {};
  if (profile.archived === true) return;
  // An evaluation from a previous internship must not complete the current one.
  const currentAcademicYear = String(
    user.academicYear || profile.academicYear || '',
  ).trim();
  if (
    !currentAcademicYear ||
    !submittedAcademicYear ||
    String(submittedAcademicYear).trim() !== currentAcademicYear
  ) {
    return;
  }

  const program = String(user.program || '').trim();
  const definitions = definitionsSnapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((item) => item.active !== false)
    .filter((item) => {
      const target = String(item.program || 'All Programs').trim();
      return !target || target === 'All Programs' || target === program;
    });
  const completionDefinitions = definitions.filter(isCompletionDefinition);
  const requirements = requirementsSnapshot.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((item) =>
      item.archived !== true &&
      String(item.academicYear || '').trim() === currentAcademicYear
    );

  const latestFor = (definition) => requirements
    .filter((record) =>
      record.definitionId === definition.id ||
      (!record.definitionId &&
        String(record.title || '').trim().toLowerCase() ===
          String(definition.title || '').trim().toLowerCase()))
    .sort((a, b) => {
      const aMillis = a.submittedAt?.toMillis?.() || 0;
      const bMillis = b.submittedAt?.toMillis?.() || 0;
      return bMillis - aMillis;
    })[0];

  const completionVerified = completionDefinitions.length === 0 ||
    completionDefinitions.every((definition) => latestFor(definition)?.status === 'verified');

  const approvedHours = dtrSnapshot.docs
    .map((doc) => doc.data())
    .filter((record) =>
      record.archived !== true &&
      record.status === 'verified' &&
      String(record.academicYear || '').trim() === currentAcademicYear
    )
    .reduce((sum, record) => sum + creditedHours(record), 0);
  const requiredHours = Number(profile.requiredHours || 400);

  const deploymentDefinitions = definitions.filter(
    (definition) =>
      !isOngoingDefinition(definition) &&
      !isCompletionDefinition(definition)
  );
  const prerequisites = deploymentDefinitions.length === 0
    ? definitions
    : deploymentDefinitions;
  const prerequisitesVerified = prerequisites.length > 0 &&
    prerequisites.every(
      (definition) => latestFor(definition)?.status === 'verified'
    );

  const placementStatus = String(
    profile.placementStatus || 'Unassigned'
  ).toLowerCase();
  const placementConfirmed = ['confirm', 'deploy', 'ongoing', 'active']
    .some((term) => placementStatus.includes(term));

  if (
    !prerequisitesVerified ||
    !placementConfirmed ||
    approvedHours < requiredHours ||
    !completionVerified
  ) {
    await profileDoc.ref.update({
      statusSyncPending: false,
      updatedAt: FieldValue.serverTimestamp(),
    }, { lastUpdateTime: profileDoc.updateTime });
    return;
  }

  await profileDoc.ref.update({
    status: 'Completed',
    completedAt: profile.completedAt || FieldValue.serverTimestamp(),
    statusSyncPending: false,
    updatedAt: FieldValue.serverTimestamp(),
  }, { lastUpdateTime: profileDoc.updateTime });

  await db.collection('notifications').add({
    title: 'Internship status updated',
    message: 'Your internship status is now Completed.',
    targetRole: 'user:' + studentId,
    targetUserId: studentId,
    type: 'status_update',
    relatedId: studentId,
    priority: 'normal',
    active: true,
    readBy: [],
    createdBy: 'system:evaluation-api',
    createdAt: FieldValue.serverTimestamp(),
  });
}

function parseBody(body) {
  if (body && typeof body === 'object') return body;
  if (typeof body === 'string' && body.trim()) return JSON.parse(body);
  return {};
}

function normalizeToken(value) {
  const token = String(value || '').trim();
  return /^[A-Za-z0-9_-]{20,160}$/.test(token) ? token : '';
}

function iso(value) {
  if (value instanceof Timestamp) return value.toDate().toISOString();
  if (value?.toDate) return value.toDate().toISOString();
  return null;
}

function publicPayload(id, data) {
  return {
    token: id,
    pdfRequired: Boolean(data.templatePath),
    program: data.program || '', startDate: iso(data.startDate), endDate: iso(data.endDate),
    studentName: String(data.studentName || 'Student Intern'),
    companyName: String(data.companyName || ''),
    supervisorName: String(data.supervisorName || 'Industry Supervisor'),
    status: String(data.status || 'pending'),
    expiresAt: iso(data.expiresAt),
    submittedAt: iso(data.submittedAt),
    archived: data.archived === true,
  };
}

async function authorizeStaff(authorization) {
  ensureAdminApp();

  const bearer = typeof authorization === 'string'
    ? authorization.match(/^Bearer\s+(\S+)$/i)?.[1]
    : null;

  if (!bearer) {
    return {
      status: 401,
      payload: { error: 'Staff sign-in is required.' },
    };
  }

  let decoded;
  try {
    decoded = await getAuth().verifyIdToken(bearer, true);
  } catch (_) {
    return {
      status: 401,
      payload: { error: 'Your session is invalid or expired. Sign in again.' },
    };
  }

  const db = getFirestore();
  const staffSnapshot = await db.collection('users').doc(decoded.uid).get();
  const staff = staffSnapshot.data() || {};

  const isAdmin = staff.role === 'admin';
  const isCoordinator =
    staff.role === 'coordinator' &&
    staff.approvalStatus === 'approved';

  if (!staffSnapshot.exists ||
      staff.active !== true ||
      (!isAdmin && !isCoordinator)) {
    return {
      status: 403,
      payload: { error: 'Only active, authorized internship staff can create evaluations.' },
    };
  }

  return { db, uid: decoded.uid, isCoordinator };
}

export async function createStaffEvaluation({ authorization, body }) {
  const staff = await authorizeStaff(authorization);
  if (staff.status) return staff;
  const { db, uid, isCoordinator } = staff;
  let parsed;
  try {
    parsed = parseBody(body);
  } catch (_) {
    return {
      status: 400,
      payload: { error: 'Invalid evaluation request.' },
    };
  }

  const studentId = String(parsed.studentId || '').trim();
  const companyName = String(parsed.companyName || '').trim();
  const supervisorName = String(parsed.supervisorName || '').trim();
  const supervisorEmail = String(parsed.supervisorEmail || '').trim().toLowerCase();
  const validDays = Number(parsed.validDays ?? 14);

  if (!studentId ||
      !companyName ||
      !supervisorName ||
      !singleMailbox(supervisorEmail) ||
      !Number.isInteger(validDays) ||
      validDays < 1 ||
      validDays > 60) {
    return {
      status: 400,
      payload: { error: 'Complete all supervisor evaluation details.' },
    };
  }

  const studentSnapshot = await db.collection('users').doc(studentId).get();
  const student = studentSnapshot.data() || {};

  if (!studentSnapshot.exists ||
      student.role !== 'student' ||
      student.active === false) {
    return {
      status: 404,
      payload: { error: 'An active student intern was not found.' },
    };
  }

  if (isCoordinator && student.coordinatorId !== uid) {
    return {
      status: 403,
      payload: { error: 'This student is not assigned to your coordinator account.' },
    };
  }

  const academicYear = String(student.academicYear || '').trim();
  if (!academicYear) {
    return {
      status: 409,
      payload: { error: 'Set the student academic year before creating an evaluation.' },
    };
  }

  const profileSnapshot =
    await db.collection('internship_profiles').doc(studentId).get();
  const profile = profileSnapshot.data() || {};
  const profileYear = String(profile.academicYear || '').trim();

  if (profile.archived === true ||
      (profileYear && profileYear !== academicYear)) {
    return {
      status: 409,
      payload: { error: 'The student internship profile must be reviewed before creating an evaluation.' },
    };
  }

  const token = randomBytes(24).toString('base64url');
  const evaluationRef = db.collection('supervisor_evaluations').doc(token);
  const statusRef = db.collection('evaluation_status').doc();

  const source = parsed.templatePath;
  if (typeof source !== 'string' || source.split('/').length !== 3 ||
      !source.startsWith(uid + '/form_templates/') || !/^[a-zA-Z0-9._-]+[.]pdf$/i.test(source.split('/')[2])) {
    throw invalid('Select the approved editable evaluation PDF.');
  }
  const blank = await readStoredFile(documentBucket(), source, 5 * 1024 * 1024);
  const official = await checkPdf(blank);
  if (!official.getForm().getFields().length) throw invalid('The official evaluation PDF must have editable form fields.');
  const templatePath = token + '/official.pdf';
  await storageRequest('', evaluationBucket, templatePath, {
    method:'POST', headers:{'Content-Type':'application/pdf'}, body:blank,
  });

  await db.runTransaction(async batch => {
    const currentProfile = await batch.get(profileSnapshot.ref);
    if (currentProfile.exists !== profileSnapshot.exists ||
        (currentProfile.exists && !currentProfile.updateTime.isEqual(profileSnapshot.updateTime))) {
      throw invalid('The internship changed. Refresh before creating an evaluation.', 409);
    }
    batch.set(evaluationRef, {
      templatePath,
      templateHash: digest(blank),
      pageCount: official.getPageCount(),
      formFields: official.getForm().getFields().map(field => ({
        name: field.getName(), required: field.isRequired(),
      })),
      program: student.program || '', startDate: profile.startDate ?? null, endDate: profile.endDate ?? null,
      statusId: statusRef.id,
      studentId,
      studentName: String(student.displayName || student.name || '').trim(),
      companyName,
      supervisorName,
      supervisorEmail,
      coordinatorId: student.coordinatorId || null,
      academicYear,
      status: 'pending',
      expiresAt: Timestamp.fromDate(
        new Date(Date.now() + validDays * 24 * 60 * 60 * 1000)
      ),
      archived: false,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // No secret link token or confidential supervisor information goes here.
    batch.set(statusRef, {
      studentId,
      academicYear,
      status: 'pending',
      createdAt: FieldValue.serverTimestamp(),
    });
  });

  return {
    status: 201,
    payload: { token },
  };
}
export async function getPublicEvaluation({ token }) {
  ensureAdminApp();
  const safeToken = normalizeToken(token);
  if (!safeToken) {
    return { status: 400, payload: { error: 'Invalid evaluation link.' } };
  }

  const db = getFirestore();
  const snapshot = await db.collection('supervisor_evaluations').doc(safeToken).get();
  if (!snapshot.exists) {
    return { status: 404, payload: { error: 'Evaluation link not found.' } };
  }

  const data = snapshot.data();
  const { status, expiresAt, submittedAt, archived } = publicPayload(snapshot.id, data);
  return { status: 200, payload: { token: snapshot.id, status, expiresAt, submittedAt, archived } };
}


const digest = value => createHash('sha256').update(value).digest('hex');
const mailboxRef = (db, token) => db.collection('evaluation_mailboxes').doc(token);
function unavailable(data) {
  if (!data) return { status: 404, payload: { error: 'Evaluation not found.' } };
  if (data.status === 'submitted') return { status: 409, payload: { error: 'Evaluation already submitted.' } };
  if (data.archived || !(data.expiresAt?.toMillis() > Date.now())) {
    return { status: 410, payload: { error: 'This evaluation is no longer open.' } };
  }
}

export async function sendEvaluationMail({ body, authorization }, deliver = sendSchoolEmail) {
  ensureAdminApp();
  const parsed = parseBody(body);
  const token = normalizeToken(parsed.token);
  if (!token) return { status: 400, payload: { error: 'Invalid evaluation link.' } };
  const invitation = parsed.action === 'invite';
  const staff = invitation ? await authorizeStaff(authorization) : null;
  if (staff?.status) return staff;
  const db = getFirestore();
  const code = randomBytes(6).toString('hex').toUpperCase();
  const state = mailboxRef(db, token);
  const result = await db.runTransaction(async tx => {
    const evaluation = (await tx.get(db.collection('supervisor_evaluations').doc(token))).data();
    const closed = unavailable(evaluation);
    if (closed) return closed;
    if (staff?.isCoordinator) {
      const student = (await tx.get(db.collection('users').doc(evaluation.studentId))).data();
      if (evaluation.coordinatorId !== staff.uid || student?.coordinatorId !== staff.uid) {
        return { status: 403, payload: { error: 'Evaluation is not assigned to you.' } };
      }
    }
    const email = evaluation.supervisorEmail?.trim().toLowerCase();
    if (!singleMailbox(email) || (!invitation && email !== String(parsed.email || '').trim().toLowerCase())) {
      return { status: 403, payload: { error: 'Check your registered supervisor email.' } };
    }
    const now = Date.now();
    const previous = (await tx.get(state)).data() || {};
    const field = invitation ? 'lastInvite' : 'lastCode';
    if (now - (previous[field] || 0) < 60000) {
      return { status: 429, payload: { error: 'Wait one minute before requesting another email.' } };
    }
    const sends = (previous.sends || []).filter(t => t > now - 3600000);
    if (sends.length >= 8) return { status: 429, payload: { error: 'Email limit reached. Try again later.' } };
    tx.set(state, { [field]: now, sends: [...sends, now], ...(!invitation && {
      codeHash: digest(code), codeUntil: now + 600000, attempts: 0, codeEmail: email,
    }) }, { merge: true });
    return { email, studentName: evaluation.studentName };
  });
  if (result.status) return result;
  let text;
  if (invitation) {
    const origin = process.env.APP_ORIGIN;
    if (!origin || !origin.startsWith('https://')) return { status: 503, payload: { error: 'Configure the public HTTPS app origin before sending invitations.' } };
    const url = new URL('/', origin);
    url.searchParams.set('evaluation', token);
    text = `Please complete the supervisor evaluation for ${result.studentName} in Practicum Connect. Open ${url} and request a verification code at this email address.`;
  } else {
    text = `Your Practicum Connect supervisor verification code is ${code}. It expires in 10 minutes. Enter it only in your evaluation form.`;
  }
  try {
    await deliver({ to: result.email, subject: invitation ? 'Practicum Connect supervisor evaluation' : 'Your supervisor verification code', text });
    return { status: 200, payload: { sent: true } };
  } catch {
    return { status: 503, payload: { error: 'Email could not be sent. Check the school mail configuration and retry after one minute.' } };
  }
}

export async function verifyPublicEvaluationAccess({ body }) {
  ensureAdminApp();
  const parsed = parseBody(body);
  const token = normalizeToken(parsed.token);
  if (!token) return { status: 400, payload: { error: 'Invalid link.' } };
  const db = getFirestore();
  const state = mailboxRef(db, token);
  return db.runTransaction(async tx => {
    const data = (await tx.get(db.collection('supervisor_evaluations').doc(token))).data();
    const closed = unavailable(data);
    if (closed) return closed;
    const mailbox = (await tx.get(state)).data() || {};
    const email = String(parsed.email || '').trim().toLowerCase();
    const invalid = { status: 403, payload: { error: 'Invalid or expired code. Check the latest email or request another code.' } };
    if (email !== mailbox.codeEmail || email !== data.supervisorEmail?.trim().toLowerCase() ||
        !mailbox.codeHash || mailbox.attempts >= 5 || mailbox.codeUntil <= Date.now()) return invalid;
    if (digest(String(parsed.code || '').trim().toUpperCase()) !== mailbox.codeHash) {
      tx.update(state, { attempts: mailbox.attempts + 1 });
      return invalid;
    }
    const proof = randomBytes(32).toString('base64url');
    tx.update(state, { codeHash: FieldValue.delete(), proofHash: digest(proof), proofUntil: Date.now() + 3600000, proofEmail: email });
    return { status: 200, payload: { authorized: true, proof, ...publicPayload(token,data) } };
  });
}

async function verifiedPdfAccess(db, token, input) {
  const data = (await db.collection('supervisor_evaluations').doc(token).get()).data();
  const closed = unavailable(data);
  if (closed) throw invalid(closed.payload.error, closed.status);
  const mailbox = (await mailboxRef(db, token).get()).data();
  const email = String(input.email || '').trim().toLowerCase();
  if (!mailbox || !email || email !== mailbox.proofEmail ||
      email !== data.supervisorEmail?.trim().toLowerCase() ||
      !(mailbox.proofUntil > Date.now()) || mailbox.proofHash !== digest(String(input.proof || ''))) {
    throw invalid('Verify your mailbox again to continue.', 403);
  }
  if (!data.templatePath) throw invalid('This invitation uses the legacy rating form.');
  return data;
}

async function evaluationFileAction(authorization, input) {
  const token = normalizeToken(input.token);
  if (!token) throw invalid('Invalid evaluation link.');
  if (input.action === 'staffPdf') {
    const staff = await authorizeStaff(authorization);
    if (staff.status) return staff;
    const record = (await staff.db.collection('supervisor_evaluations').doc(token).get()).data();
    if (!record?.completedPath || record.status !== 'submitted') throw invalid('Completed PDF unavailable.', 404);
    const student = (await staff.db.collection('users').doc(record.studentId).get()).data();
    if (staff.isCoordinator && (student?.coordinatorId !== staff.uid || record.coordinatorId !== staff.uid)) {
      throw invalid('This evaluation is outside your assignment.', 403);
    }
    return {status:200, payload:{url:await signedFileUrl(record.completedPath)}};
  }
  ensureAdminApp();
  const data = await verifiedPdfAccess(getFirestore(), token, input);
  if (input.action === 'officialPdf') return {status:200, payload:{url:await signedFileUrl(data.templatePath)}};
  const uploadId = randomBytes(20).toString('hex');
  const url = await signedFileUrl(token + '/' + uploadId + '.pdf', true);
  return {status:200, payload:{uploadId,url}};
}

export async function submitPublicEvaluation({ body }) {
  ensureAdminApp();
  const parsed = parseBody(body);
  const token = normalizeToken(parsed.token);
  const email = String(parsed.email || '').trim().toLowerCase();
  const comments = String(parsed.comments || '').trim();
  const ratings = parsed.ratings && typeof parsed.ratings === 'object'
    ? parsed.ratings
    : {};

  if (!token || !email.includes('@')) {
    return {
      status: 400,
      payload: { error: 'A valid evaluation link and registered supervisor email are required.' },
    };
  }
  if (comments.length > 3000) {
    return { status: 400, payload: { error: 'Comments must be 3000 characters or fewer.' } };
  }

  const db = getFirestore();
  const ref = db.collection('supervisor_evaluations').doc(token);

  try {
    const initial = (await ref.get()).data();
    let completedPath;
    let completedHash;
    const normalizedRatings = {};
    if (initial?.templatePath) {
      await verifiedPdfAccess(db, token, parsed);
      if (parsed.confirmed !== true || !/^[a-f0-9]{40}$/.test(parsed.uploadId || '')) {
        throw invalid('Upload and confirm the completed PDF before submitting.');
      }
      completedPath = token + '/' + parsed.uploadId + '.pdf';
      const bytes = await readStoredFile(evaluationBucket, completedPath, 10 * 1024 * 1024);
      const completed = await checkPdf(bytes);
      if (completed.getPageCount() !== initial.pageCount) throw invalid('Upload all pages of the official form.');
      const fields = completed.getForm().getFields();
      // Flattened or scanned copies have no interactive fields. The supervisor
      // reviews their visible contents before confirming the submission.
      if (fields.length) {
        const byName = new Map(fields.map(field => [field.getName(), field]));
        for (const item of initial.formFields) {
          const field = byName.get(item.name);
          if (!field) throw invalid('The uploaded PDF does not match the official form.');
          if (!item.required) continue;
          let value;
          if (field.getText) value = field.getText()?.trim();
          else if (field.isChecked) value = field.isChecked();
          else if (field.getSelected) value = field.getSelected()?.length;
          else value = field.acroField.getValue();
          if (!value) {
            throw invalid('Complete the required field: ' + item.name);
          }
        }
      }
      completedHash = digest(bytes);
      if (completedHash === initial.templateHash) throw invalid('Upload the completed copy of the official form.');
    } else {
      const required = ['professionalism', 'workQuality', 'attendance', 'communication', 'initiative'];
      for (const key of required) {
        const value = Number(ratings[key]);
        if (!Number.isInteger(value) || value < 1 || value > 5) {
          return { status: 400, payload: { error: 'Every rating must be an integer from 1 to 5.' } };
        }
        normalizedRatings[key] = value;
      }
    }
    const result = await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        return { status: 404, payload: { error: 'Evaluation link not found.' } };
      }
      const data = snapshot.data();
      if (data.archived === true) {
        return { status: 410, payload: { error: 'This evaluation record has been archived.' } };
      }
      if (data.status === 'submitted') {
        return { status: 409, payload: { error: 'This evaluation was already submitted and is locked.' } };
      }
      const expiresAt = data.expiresAt?.toDate?.();
      if (!(expiresAt instanceof Date) || expiresAt.getTime() <= Date.now()) {
        return { status: 410, payload: { error: 'This evaluation link has expired.' } };
      }
      const expectedEmail = String(data.supervisorEmail || '').trim().toLowerCase();
      if (!expectedEmail || email !== expectedEmail) {
        return {
          status: 403,
          payload: { error: 'The email address does not match the supervisor authorized for this evaluation.' },
        };
      }

      const state = mailboxRef(db, token);
      const mailbox = (await transaction.get(state)).data();
      if (!mailbox || mailbox.proofEmail !== email || !(mailbox.proofUntil > Date.now()) ||
          mailbox.proofHash !== digest(String(parsed.proof || ''))) {
        return { status: 403, payload: { error: 'Verify your mailbox again to submit.' } };
      }

      const studentId = String(data.studentId || '').trim();
      if (!studentId || studentId.includes('/')) {
        return { status: 400, payload: { error: 'Invalid student record.' } };
      }

      // Each evaluation has a separate student-readable status record.
      // Older pending evaluations may not have a statusId yet.
      const statusId = String(data.statusId || '').trim();
      const statusCollection = db.collection('evaluation_status');
      const statusRef = statusId
        ? statusCollection.doc(statusId)
        : statusCollection.doc();

      if (statusId) {
        // Complete all transaction reads before performing any writes.
        const statusSnapshot = await transaction.get(statusRef);
        const existingStatus = statusSnapshot.data();

        if (
          !statusSnapshot.exists ||
          existingStatus.studentId !== studentId ||
          existingStatus.academicYear !== String(data.academicYear || '').trim() ||
          existingStatus.status !== 'pending'
        ) {
          return {
            status: 409,
            payload: { error: 'Evaluation status record is missing or inconsistent.' },
          };
        }
      }

      // Never put ratings, comments, supervisor email, or the private
      // evaluation link token in the student-readable status record.
      transaction.delete(state);
      transaction.set(statusRef, {
        studentId,
        academicYear: String(data.academicYear || '').trim(),
        status: 'submitted',
        submittedAt: FieldValue.serverTimestamp(),
        ...(!statusId
          ? { createdAt: FieldValue.serverTimestamp() }
          : {}),
      }, { merge: true });
      transaction.update(ref, {
        statusId: statusRef.id,
        ...(completedPath ? {completedPath, completedHash} : {ratings: normalizedRatings}),
        comments,
        status: 'submitted',
        submittedAt: FieldValue.serverTimestamp(),
        statusSyncPending: true,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        status: 200,
        studentId: String(data.studentId || ''),
      evaluationAcademicYear: String(data.academicYear || '').trim(),
        payload: {
          ok: true,
          message: 'Evaluation submitted successfully. This form is now locked.',
        },
      };
    });
    if (result.status === 200 && result.studentId) {
      try {
        await syncCompletionStage(db, result.studentId, result.evaluationAcademicYear);
      } catch (syncError) {
        console.error('Unable to synchronize internship completion stage:', syncError);
      }
    }
    return { status: result.status, payload: result.payload };
  } catch (error) {
    if (error.httpStatus) return {status:error.httpStatus,payload:{error:error.message}};
    return {
      status: 500,
      payload: { error: error instanceof Error ? error.message : String(error) },
    };
  }
}

export async function handleEvaluationAction({authorization,body}) {
  let parsed;
  try { parsed = parseBody(body); }
  catch { return {status:400,payload:{error:'Invalid evaluation request.'}}; }
  switch (parsed?.action) {
    case 'officialPdf':
    case 'uploadPdf':
    case 'staffPdf': return evaluationFileAction(authorization,parsed);
    case 'create': return createStaffEvaluation({authorization,body:parsed});
    case 'requestCode':
    case 'invite': return sendEvaluationMail({authorization,body:parsed});
    case 'verify': return verifyPublicEvaluationAccess({body:parsed});
    case undefined:
    case 'submit': return submitPublicEvaluation({body:parsed});
    default: return {status:400,payload:{error:'Unknown evaluation action.'}};
  }
}
