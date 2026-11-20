import { validAcademicYear } from '../functions/attendance.mjs';
import './trusted_certificates.mjs';
import { applicationDefault, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';

function ensureAdminApp() {
  if (getApps().length > 0) return getApps()[0];
  const json = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (json) {
    const account = JSON.parse(json);
    return initializeApp({ credential: cert(account), projectId: account.project_id });
  }
  const projectId = process.env.FIREBASE_PROJECT_ID?.trim() || 'practicumconnect-aa5d1';
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL?.trim();
  const privateKey = process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n');
  if (projectId && clientEmail && privateKey) {
    return initializeApp({ credential: cert({ projectId, clientEmail, privateKey }), projectId });
  }
  return initializeApp({ credential: applicationDefault(), projectId: projectId || undefined });
}

function tokenFromHeader(header) {
  if (typeof header !== 'string') return null;
  const [scheme, value] = header.split(' ');
  return scheme?.toLowerCase() === 'bearer' && value ? value : null;
}

function parseBody(body) {
  if (body && typeof body === 'object') return body;
  if (typeof body === 'string' && body.trim()) return JSON.parse(body);
  return {};
}

function partsAt(date, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    weekday: 'short', hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date);
  return Object.fromEntries(parts.map(({ type, value }) => [type, value]));
}

function dayKey(date, timeZone) {
  const p = partsAt(date, timeZone);
  return `${p.year}-${p.month}-${p.day}`;
}

function weekdayNumber(weekday) {
  return ({ Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 })[weekday];
}

// Convert a local wall-clock date/time in an IANA zone into a UTC instant.
function zonedWallTime(dateKeyValue, minuteOfDay, timeZone) {
  const [year, month, day] = dateKeyValue.split('-').map(Number);
  const hour = Math.floor(minuteOfDay / 60);
  const minute = minuteOfDay % 60;
  const desired = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  let guess = desired;
  for (let i = 0; i < 5; i += 1) {
    const p = partsAt(new Date(guess), timeZone);
    const represented = Date.UTC(
      Number(p.year), Number(p.month) - 1, Number(p.day),
      Number(p.hour), Number(p.minute), Number(p.second),
    );
    const next = desired - (represented - guess);
    if (next === guess) break;
    guess = next;
  }
  return new Date(guess);
}

async function resolveActor(authorization) {
  ensureAdminApp();
  const token = tokenFromHeader(authorization);
  if (!token) return { error: [401, 'A signed-in account is required.'] };
  const auth = getAuth();
  const db = getFirestore();
  const decoded = await auth.verifyIdToken(token, true);
  const snapshot = await db.collection('users').doc(decoded.uid).get();
  const profile = snapshot.data();
  if (!snapshot.exists || profile?.active !== true) {
    return { error: [403, 'This account is inactive or its Practicum Connect profile is missing.'] };
  }
  if (profile.role === 'student' && (profile.enrollmentStatus !== 'active' || !decoded.student_enrolled || !decoded.email_verified)) {
    return { error: [403, 'Activate your roster account before recording attendance.'] };
  }
  return { auth, db, uid: decoded.uid, profile, idToken: token };
}

async function verifyCheckInPhoto(actor, photoPath) {
  const projectUrl = process.env.SUPABASE_URL?.trim();
  const apiKey = (process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY)?.trim();
  if (!projectUrl || !apiKey) throw Object.assign(new Error('DTR backend is missing Supabase Storage configuration.'), { httpStatus: 503 });
  const bucket = (process.env.SUPABASE_BUCKET || 'PracticumConnectStorage').trim();
  const encodedPath = photoPath.split('/').map(encodeURIComponent).join('/');
  const url = `${projectUrl.replace(/\/$/, '')}/storage/v1/object/authenticated/${encodeURIComponent(bucket)}/${encodedPath}`;
  const headers = { apikey: apiKey, Authorization: `Bearer ${actor.idToken}` };
  const response = await fetch(url, {
    method: 'GET',
    headers: { ...headers, Range: 'bytes=0-0' },
  });
  if (response.body) await response.body.cancel();
  if (!response.ok) throw Object.assign(new Error('The check-in photo could not be verified in private storage. Please retake it and try again.'), { httpStatus: 400 });
  const contentType = response.headers.get('content-type') || '';
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (!contentType.startsWith('image/') || (contentLength > 0 && contentLength > 5 * 1024 * 1024)) {
    throw Object.assign(new Error('The stored check-in image is invalid or too large.'), { httpStatus: 400 });
  }
}

function responseError(status, error) {
  return { status, payload: { error } };
}

async function notifyCoordinator(db, coordinatorId, studentName, title, message, relatedId) {
  if (!coordinatorId) return;
  await db.collection('notifications').add({
    title,
    message,
    createdAt: FieldValue.serverTimestamp(),
    targetRole: `user:${coordinatorId}`,
    targetUserId: coordinatorId,
    type: 'dtr_submission',
    relatedId,
    priority: 'normal',
    readBy: [],
    dismissedBy: [],
    active: true,
    createdBy: 'system:dtr-attendance',
    studentName,
  });
}

async function clockIn(actor, body) {
  if (actor.profile.role !== 'student') return responseError(403, 'Only a student intern can sign in.');
  const photoPath = String(body.photoPath || '').trim();
  if (!photoPath.startsWith(`${actor.uid}/dtr-checkins/`) || !photoPath.endsWith('.jpg')) {
    return responseError(400, 'Capture a check-in photo before signing in.');
  }
  await verifyCheckInPhoto(actor, photoPath);
  const { db, uid, profile: user } = actor;
  if (!user.coordinatorId) return responseError(409, 'Ask your coordinator to assign your internship before signing in.');
  const placementSnapshot = await db.collection('internship_profiles').doc(uid).get();
  const placement = placementSnapshot.data();
  if (!placementSnapshot.exists || placement?.archived === true) {
    return responseError(409, 'Your active internship details are unavailable. Ask your coordinator to update your profile.');
  }
  const academicYear = user.academicYear?.trim();
  if (!validAcademicYear(academicYear) || (placement.academicYear && placement.academicYear !== academicYear)) {
    return responseError(409, 'Ask your coordinator to confirm the assigned academic year.');
  }
  const startMinute = Number(placement.shiftStartMinutes);
  const endMinute = Number(placement.shiftEndMinutes);
  const workDays = Array.isArray(placement.workDays) ? placement.workDays.map(Number) : [];
  const timeZone = String(placement.timeZone || 'Asia/Manila').trim();
  if (!Number.isInteger(startMinute) || !Number.isInteger(endMinute) || startMinute < 0 || endMinute > 1439 || startMinute >= endMinute || workDays.length === 0) {
    return responseError(409, 'Your coordinator needs to set valid shift hours and work days in Internship Details first.');
  }
  try { new Intl.DateTimeFormat('en', { timeZone }); } catch (_) {
    return responseError(409, 'The internship profile has an invalid time zone. Ask your coordinator to correct it.');
  }
  const now = new Date();
  const parts = partsAt(now, timeZone);
  if (!workDays.includes(weekdayNumber(parts.weekday))) {
    return responseError(409, 'Today is not one of your scheduled internship work days.');
  }
  const workDate = `${parts.year}-${parts.month}-${parts.day}`;
  const scheduledStartAt = zonedWallTime(workDate, startMinute, timeZone);
  const scheduledEndAt = zonedWallTime(workDate, endMinute, timeZone);
  if (now < scheduledStartAt) return responseError(409, 'Sign In is available at your scheduled shift start.');

  if (now >= scheduledEndAt) return responseError(409, 'The scheduled shift has already ended.');
  const tomorrow = new Date(Date.parse(workDate + 'T00:00:00Z') + 86400000).toISOString().slice(0,10);
  const reference = db.collection('dtr_entries').doc(`${uid}_${workDate}`);
  const lock = db.collection('dtr_attendance_locks').doc(`${uid}_${workDate}`);
  const legacy = await db.collection('dtr_entries').where('studentId', '==', uid).get();
  const existingToday = legacy.docs.some((doc) => {
    const data = doc.data();
    if (data.archived === true) return false;
    if (data.workDate === workDate) return true;
    const stamp = data.timeIn?.toDate?.() || data.date?.toDate?.();
    return stamp instanceof Date && dayKey(stamp, timeZone) === workDate;
  });
  if (legacy.docs.some(doc => !doc.data().archived && doc.data().attendanceState === 'in_progress')) {
    return responseError(409, 'Resolve the open shift before starting another.');
  }
  if (existingToday) return responseError(409, 'A DTR record already exists for today.');

  const name = String(user.displayName || 'Student').trim().slice(0, 120);
  await db.runTransaction(async (transaction) => {
    const latestPlacement = await transaction.get(placementSnapshot.ref);
    if (!latestPlacement.updateTime?.isEqual(placementSnapshot.updateTime)) {
      throw Object.assign(new Error('The internship changed. Refresh before signing in.'), {httpStatus:409});
    }
    const [lockSnapshot, recordSnapshot] = await Promise.all([transaction.get(lock), transaction.get(reference)]);
    if (lockSnapshot.exists || recordSnapshot.exists) throw new Error('DTR_EXISTS');
    transaction.create(lock, { studentId: uid, workDate, createdAt: FieldValue.serverTimestamp() });
    transaction.create(reference, {
      studentId: uid,
      studentName: name,
      coordinatorId: user.coordinatorId,
      academicYear,
      workDayEnd: Timestamp.fromDate(zonedWallTime(tomorrow, 0, timeZone)),
      date: Timestamp.fromDate(zonedWallTime(workDate, 0, timeZone)),
      workDate,
      timeIn: Timestamp.fromDate(now),
      timeOut: null,
      breakMinutes: 0,
      attendanceState: 'in_progress',
      scheduledStartAt: Timestamp.fromDate(scheduledStartAt),
      scheduledEndAt: Timestamp.fromDate(scheduledEndAt),
      scheduleTimeZone: timeZone,
      checkInPhotoPath: photoPath,
      status: 'pending',
      remarks: null,
      archived: false,
      createdBy: uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }).catch((error) => {
    if (error?.message === 'DTR_EXISTS') throw Object.assign(new Error('A DTR record already exists for today.'), { httpStatus: 409 });
    throw error;
  });
  await notifyCoordinator(db, user.coordinatorId, name, 'Student signed in', `${name} signed in for the ${workDate} shift.`, reference.id);
  return { status: 200, payload: { ok: true, recordId: reference.id, message: 'Sign In recorded with server time.' } };
}

async function clockOut(actor) {
  if (actor.profile.role !== 'student') return responseError(403, 'Only a student intern can sign out.');
  const { db, uid, profile } = actor;
  const studentRecords = await db.collection('dtr_entries').where('studentId', '==', uid).get();
  const openDocs = studentRecords.docs.filter((doc) => doc.data().archived !== true && doc.data().attendanceState === 'in_progress');
  if (openDocs.length === 0) return responseError(409, 'There is no open DTR shift to sign out from.');
  if (openDocs.length > 1) return responseError(409, 'Multiple open shifts were found. Ask your coordinator to review your DTR records.');
  const reference = openDocs[0].ref;
  const now = new Date();
  const openRecord = openDocs[0].data();
  const timeZone = openRecord.scheduleTimeZone || 'Asia/Manila';
  if (openRecord.workDate && dayKey(now, timeZone) !== openRecord.workDate) {
    return responseError(409, 'This shift missed its scheduled Sign Out date. Ask your coordinator to resolve it with a reason.');
  }
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    const record = snapshot.data();
    if (!snapshot.exists || record.archived === true || record?.attendanceState !== 'in_progress') throw new Error('SHIFT_CLOSED');
    const endAt = record.scheduledEndAt?.toDate?.();
    if (!(endAt instanceof Date) || now < endAt) throw new Error('SHIFT_NOT_ENDED');
    transaction.update(reference, {
      timeOut: Timestamp.fromDate(now),
      attendanceState: 'submitted',
      status: 'pending',
      updatedAt: FieldValue.serverTimestamp(),
      submittedAt: FieldValue.serverTimestamp(),
    });
  }).catch((error) => {
    if (error?.message === 'SHIFT_NOT_ENDED') throw Object.assign(new Error('Sign Out becomes available at your scheduled shift end.'), { httpStatus: 409 });
    if (error?.message === 'SHIFT_CLOSED') throw Object.assign(new Error('This shift is already closed.'), { httpStatus: 409 });
    throw error;
  });
  const record = openDocs[0].data();
  await notifyCoordinator(db, record.coordinatorId || profile.coordinatorId, record.studentName || 'Student', 'DTR submitted for review', `${record.studentName || 'A student'} signed out and submitted a Daily Time Record for review.`, reference.id);
  return { status: 200, payload: { ok: true, message: 'Sign Out recorded with server time and sent for coordinator review.' } };
}

async function closeEarly(actor, body) {
  if (!['admin', 'coordinator'].includes(actor.profile.role)) return responseError(403, 'Only an authorized coordinator can close a shift early.');
  if (actor.profile.role === 'coordinator' && actor.profile.approvalStatus !== 'approved') {
    return responseError(403, 'Only an approved Program Coordinator can close a shift early.');
  }
  const recordId = String(body.recordId || '').trim();
  const reason = String(body.reason || '').trim();
  if (!recordId || reason.length < 8) return responseError(400, 'A DTR record and a reason of at least eight characters are required.');
  const { db, uid, profile } = actor;
  const reference = db.collection('dtr_entries').doc(recordId);
  const snapshot = await reference.get();
  const record = snapshot.data();
  if (!snapshot.exists || record.archived === true || record?.attendanceState !== 'in_progress') return responseError(409, 'The selected shift is no longer open.');
  const student = (await db.collection('users').doc(record.studentId).get()).data();
  if (actor.profile.role === 'coordinator' && (record.coordinatorId !== uid || student?.coordinatorId !== uid)) {
    return responseError(403, 'You can close early only shifts belonging to your assigned interns.');
  }
  const now = new Date();
  const scheduledEndAt = record.scheduledEndAt?.toDate?.();
  const missedClockOut = Boolean(
    record.workDate &&
    dayKey(now, record.scheduleTimeZone || 'Asia/Manila') !== record.workDate,
  );
  const actualTime = String(body.actualTime || '').trim();
  if ((missedClockOut || actualTime) && !/^([01]\d|2[0-3]):[0-5]\d$/.test(actualTime)) {
    return responseError(400, 'Enter the actual sign-out time on the original shift date (HH:mm).');
  }
  const [hour, minute] = actualTime.split(':').map(Number);
  const end = actualTime ? zonedWallTime(record.workDate, hour*60+minute,record.scheduleTimeZone || 'Asia/Manila') : now;
  const start = record.timeIn?.toDate?.();
  if (!(start instanceof Date) || end <= start || end > now ||
      dayKey(end,record.scheduleTimeZone || 'Asia/Manila') !== record.workDate) {
    return responseError(400, 'Sign-out must follow check-in on the original work date and cannot be in the future.');
  }
  await reference.update({
    timeOut: Timestamp.fromDate(end),
    attendanceState: 'submitted',
    status: 'pending',
    earlyClockOut: scheduledEndAt instanceof Date && end < scheduledEndAt,
    missedClockOut,
    exceptionReason: reason,
    exceptionBy: uid,
    exceptionAt: FieldValue.serverTimestamp(),
    remarks: `Coordinator attendance exception: ${reason}`,
    updatedAt: FieldValue.serverTimestamp(),
    submittedAt: FieldValue.serverTimestamp(),
  }, {lastUpdateTime:snapshot.updateTime});
  await db.collection('notifications').add({
    title: 'Coordinator closed shift early',
    message: `Your shift was closed early by ${profile.displayName || 'your coordinator'}. Reason: ${reason}`,
    createdAt: FieldValue.serverTimestamp(),
    targetRole: `user:${record.studentId}`,
    targetUserId: record.studentId,
    type: 'dtr_submission',
    relatedId: reference.id,
    priority: 'normal',
    readBy: [],
    dismissedBy: [],
    active: true,
    createdBy: uid,
  });
  return { status: 200, payload: { ok: true, message: 'The shift was closed early and recorded for review.' } };
}

async function revisionResponse(actor, body) {
  if (actor.profile.role !== 'student') return responseError(403, 'Only a student intern can reply to a DTR review.');
  const recordId = String(body.recordId || '').trim();
  const responseText = String(body.response || '').trim();
  if (!recordId || responseText.length < 8 || responseText.length > 1200) {
    return responseError(400, 'Add an explanation between 8 and 1,200 characters.');
  }
  const reference = actor.db.collection('dtr_entries').doc(recordId);
  const snapshot = await reference.get();
  const record = snapshot.data();
  if (!snapshot.exists || record?.studentId !== actor.uid) return responseError(404, 'Your DTR record was not found.');
  if (record.archived === true) return responseError(409, 'Archived attendance is read-only.');
  if (!['needs_revision', 'rejected'].includes(record.status)) return responseError(409, 'This DTR is not waiting for a student response.');
  const coordinatorId = record.coordinatorId || actor.profile.coordinatorId;
  if (!coordinatorId) return responseError(409, 'Your assigned coordinator is unavailable.');
  await reference.update({
    studentResponse: responseText,
    studentRespondedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, {lastUpdateTime:snapshot.updateTime});
  await notifyCoordinator(
    actor.db,
    coordinatorId,
    record.studentName || actor.profile.displayName || 'Student',
    'Student replied to a DTR review',
    `${record.studentName || 'A student'} replied to the returned DTR. Review the response before changing its status.`,
    recordId,
  );
  return { status: 200, payload: { ok: true, message: 'Your response was sent to your coordinator.' } };
}

export async function handleDtrAttendance({ authorization, body }) {
  try {
    const actor = await resolveActor(authorization);
    if (actor.error) return responseError(actor.error[0], actor.error[1]);
    const parsed = parseBody(body);
    const action = String(parsed.action || '').trim().toLowerCase();
    if (action === 'clock_in') return await clockIn(actor, parsed);
    if (action === 'clock_out') return await clockOut(actor);
    if (action === 'close_early') return await closeEarly(actor, parsed);
    if (action === 'revision_response') return await revisionResponse(actor, parsed);
    return responseError(400, 'Unknown DTR attendance action.');
  } catch (error) {
    const status = Number(error?.httpStatus) || 500;
    return { status, payload: { error: error instanceof Error ? error.message : String(error) } };
  }
}
