import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { createInterface } from 'node:readline';

if (getApps().length === 0) {
  initializeApp({ credential: applicationDefault() });
}

const args = Object.fromEntries(
  process.argv.slice(2).map((entry) => {
    const [key, ...rest] = entry.replace(/^--/, '').split('=');
    return [key, rest.length ? rest.join('=') : true];
  }),
);

async function readPasswordFromStdin() {
  if (process.stdin.isTTY && typeof process.stdin.setRawMode === 'function') {
    process.stderr.write('Password: ');
    process.stdin.setRawMode(true);
    process.stdin.resume();

    return new Promise((resolve, reject) => {
      let password = '';
      const onData = (chunk) => {
        for (const character of chunk.toString()) {
          if (character === '\r' || character === '\n') {
            process.stdin.setRawMode(false);
            process.stdin.pause();
            process.stdin.off('data', onData);
            process.stderr.write('\n');
            resolve(password);
            return;
          }
          if (character === '\u0003') {
            process.stdin.setRawMode(false);
            process.stdin.pause();
            process.stdin.off('data', onData);
            reject(new Error('Password input cancelled.'));
            return;
          }
          if (character === '\u007f' || character === '\b') {
            password = password.slice(0, -1);
          } else {
            password += character;
          }
        }
      };
      process.stdin.on('data', onData);
      process.stdin.once('error', reject);
    });
  }

  const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
  return new Promise((resolve, reject) => {
    input.once('line', (password) => {
      input.close();
      resolve(password);
    });
    input.once('error', reject);
  });
}

const email = args.email?.trim();
const password = args.password ?? (
  args['password-stdin'] ? await readPasswordFromStdin() : undefined
);
const displayName = args.name?.trim() || 'School Administrator';
if (!email || !password || password.length < 6) {
  console.error(
    'Usage: node create_admin.mjs --email=admin@example.com '
      + '[--password=...] or --password-stdin '
      + '[--name="School Administrator"]',
  );
  process.exit(1);
}

const auth = getAuth();
const db = getFirestore();
let user;
try {
  user = await auth.getUserByEmail(email);
} catch (error) {
  if (error?.code !== 'auth/user-not-found') throw error;
  user = await auth.createUser({ email, password, displayName });
}

await auth.setCustomUserClaims(user.uid, {
  ...(user.customClaims || {}),
  app_role: 'admin',
  role: 'authenticated',
});
await db.collection('users').doc(user.uid).set(
  {
    email,
    displayName,
    role: 'admin',
    studentNumber: null,
    staffId: null,
    department: 'Administration',
    approvalStatus: 'approved',
    active: true,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  },
  { merge: true },
);

console.log(`Administrator ready: ${email}`);
console.log('Sign out and sign back in if this account was already signed in.');
