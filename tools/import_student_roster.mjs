import { readFile } from 'node:fs/promises';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { ensureAdminApp } from './staff_claims_core.mjs';
import { planRoster, provisionStudent } from './student_enrollment_core.mjs';
import './trusted_certificates.mjs';

const [file, ...options] = process.argv.slice(2);
if (!file || options.some((x) => !['--apply', '--migrate-existing', '--resend'].includes(x))) {
  throw new Error(
    'Usage: node tools/import_student_roster.mjs roster.json [--apply] [--migrate-existing] [--resend]',
  );
}
ensureAdminApp();
const db = getFirestore(),
  auth = getAuth();
const plan = await planRoster(db, auth, JSON.parse(await readFile(file, 'utf8')));
const legacy = plan.filter((row) => row.legacy).length;
console.log(
  `Validated ${plan.length} official roster rows, including ${legacy} existing accounts to re-invite.`,
);
if (options.includes('--apply')) {
  if (
    !process.env.RESEND_API_KEY ||
    !process.env.SCHOOL_EMAIL_FROM ||
    !process.env.APP_ORIGIN?.startsWith('https://')
  )
    throw new Error('Configure school email and public APP_ORIGIN before importing.');
  if (legacy && !options.includes('--migrate-existing'))
    throw new Error(
      'Review the existing matches. --migrate-existing resets their passwords and requires activation.',
    );
  for (const row of plan) await provisionStudent(db, auth, row, { resend: options.includes('--resend') });
  console.log('Roster import complete.');
}
