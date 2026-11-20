import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { reconcileStudent } from './stage.mjs';

const [projectId, mode] = process.argv.slice(2);
if (!projectId) throw new Error('Specify the intended Firebase project and optionally --apply.');
initializeApp({ projectId });
const db = getFirestore();
const students = await db.collection('users').where('role', '==', 'student').select().get();
console.log(`Found ${students.size} student accounts in ${projectId}.`);
if (mode === '--apply') {
  for (const doc of students.docs) await reconcileStudent(db, doc.id);
  console.log('Stage reconciliation complete.');
}
