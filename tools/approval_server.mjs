import { importOfficialRoster } from './official_roster_api.mjs';
import { activateStudent } from './student_enrollment_core.mjs';
import { ensureAdminApp } from './staff_claims_core.mjs';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import http from 'node:http';
import { readFileSync } from 'node:fs';
import { reviewCoordinatorRequest } from './coordinator_approval_core.mjs';
import { ensureStaffClaims } from './staff_claims_core.mjs';
import { getPublicEvaluation, handleEvaluationAction } from './evaluation_core.mjs';
import { handleDtrAttendance } from './dtr_attendance_core.mjs';
import { finalizeRequirement } from './requirement_submission.mjs';
import { createDocumentDownload } from './document_download_core.mjs';

// Local-only convenience: reuse the app's ignored config file for the public
// Supabase values needed to confirm a check-in image was uploaded successfully.
try {
  const localConfig = JSON.parse(readFileSync(new URL('../config/local.json', import.meta.url), 'utf8'));
  for (const [configKey, environmentKey] of [
    ['SUPABASE_URL', 'SUPABASE_URL'],
    ['SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_PUBLISHABLE_KEY'],
    ['SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY'],
    ['SUPABASE_BUCKET', 'SUPABASE_BUCKET'],
    ['FIREBASE_PROJECT_ID', 'FIREBASE_PROJECT_ID'],
  ]) {
    if (!process.env[environmentKey] && localConfig[configKey]) process.env[environmentKey] = localConfig[configKey];
  }
} catch (_) {
  // Production deployments provide these values through server environment variables.
}
process.env.FIREBASE_PROJECT_ID ||= 'practicumconnect-aa5d1';

const host = process.env.APPROVAL_HOST || '127.0.0.1';
const port = Number(process.env.APPROVAL_PORT || 8787);

function send(res, status, payload) {
  res.writeHead(status);
  res.end(JSON.stringify(payload));
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Content-Type', 'application/json; charset=utf-8');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const requestUrl = new URL(req.url || '/', `http://${req.headers.host || `${host}:${port}`}`);

  try {
    if (req.method === 'POST' && requestUrl.pathname === '/api/student-roster') {
      let raw = '';
      for await (const chunk of req) {
        raw += chunk;
        if (raw.length > 262144) return send(res, 413, {error:'Roster exceeds the file limit.'});
      }
      const result = await importOfficialRoster({ authorization: req.headers.authorization, body: JSON.parse(raw) }, host === '127.0.0.1' || host === 'localhost');
      return send(res,result.status,result.payload);
    }
    if (req.method === 'POST' && requestUrl.pathname === '/api/student-activation') {
      ensureAdminApp();
      const result = await activateStudent(getFirestore(), getAuth(), req.headers.authorization);
      send(res, result.status, result.payload);
      return;
    }
    if (req.method === 'POST' && ['/api/document-download','/api/requirement-submit'].includes(requestUrl.pathname)) {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      const action = requestUrl.pathname === '/api/requirement-submit' ? finalizeRequirement : createDocumentDownload;
      const result = await action({ authorization: req.headers.authorization, body: raw });
      res.setHeader('Cache-Control', 'no-store');
      send(res, result.status, result.payload);
      return;
    }
    if (req.method === 'POST' && requestUrl.pathname === '/api/coordinator-approval') {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      const result = await reviewCoordinatorRequest({
        authorization: req.headers.authorization,
        body: raw,
      });
      send(res, result.status, result.payload);
      return;
    }

    if (req.method === 'POST' && requestUrl.pathname === '/api/staff-claims') {
      const result = await ensureStaffClaims({
        authorization: req.headers.authorization,
      });
      send(res, result.status, result.payload);
      return;
    }

    if (req.method === 'POST' && requestUrl.pathname === '/api/dtr-attendance') {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      let parsed = {};
      try {
        parsed = raw.trim() ? JSON.parse(raw) : {};
      } catch (_) {
        send(res, 400, { error: 'Invalid JSON request body.' });
        return;
      }
      const result = await handleDtrAttendance({
        authorization: req.headers.authorization,
        body: parsed,
      });
      send(res, result.status, result.payload);
      return;
    }

    if (requestUrl.pathname === '/api/evaluation' && req.method === 'GET') {
      res.setHeader('Cache-Control','no-store');
      const result = await getPublicEvaluation({ token: requestUrl.searchParams.get('token') });
      send(res, result.status, result.payload);
      return;
    }

    if (requestUrl.pathname === '/api/evaluation' && req.method === 'POST') {
      let raw = '';
      for await (const chunk of req) raw += chunk;
      let parsed = {};
      try {
        parsed = raw.trim() ? JSON.parse(raw) : {};
      } catch (_) {
        send(res, 400, { error: 'Invalid JSON request body.' });
        return;
      }
      res.setHeader('Cache-Control','no-store');
      const result = await handleEvaluationAction({authorization:req.headers.authorization,body:parsed});
      send(res, result.status, result.payload);
      return;
    }

    send(res, 404, { error: 'Not found.' });
  } catch (error) {
    send(res, error.httpStatus || 500, {
      error: error instanceof Error ? error.message : String(error),
    });
  }
});

server.listen(port, host, () => {
  console.log(`Practicum Connect local API running at http://${host}:${port}`);
  console.log('Available routes: /api/coordinator-approval, /api/staff-claims, /api/evaluation and /api/dtr-attendance');
  console.log('Keep this terminal open while testing privileged/local API workflows.');
});
