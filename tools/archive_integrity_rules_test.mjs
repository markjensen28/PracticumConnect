import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp,
} from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-archive-' + randomUUID().slice(0, 8),
  firestore: { host:'127.0.0.1', port:8080, rules:readFileSync('firestore.rules','utf8') },
});
const year = '2024-2025';
const immutable = [
  ['requirements/r', 'verified'],
  ['dtr_entries/d', 'verified'],
  ['supervisor_evaluations/e', 'submitted'],
  ['internship_profiles/student', 'Completed'],
];
const archiveFields = () => ({archived:true, archivedAt:serverTimestamp(), archivedBy:'admin'});
try {
  await env.withSecurityRulesDisabled(async context => {
    const db=context.firestore();
    await Promise.all([
      ...['admin','coordinator','student','other'].map(uid => setDoc(doc(db,'users',uid), {
        active:true, role:uid === 'other' ? 'coordinator' : uid, coordinatorId:'coordinator',
        approvalStatus:'approved', enrollmentStatus:'active',
      })),
      ...immutable.map(([path,status]) => setDoc(doc(db,path), {
        studentId:'student', coordinatorId:'coordinator', academicYear:year, status,
        ...(path === 'requirements/r' && {storagePath:'student/requirements/1_pdf.pdf'}),
        // Legacy records may omit the archived flag.
      })),
      setDoc(doc(db,'requirement_versions','previous'),{
        requirementId:'r',version:1,storagePath:'student/requirements/0_pdf.pdf',
      }),
    ]);
  });
  const admin=env.authenticatedContext('admin').firestore();
  const coordinator=env.authenticatedContext('coordinator').firestore();
  const other=env.authenticatedContext('other').firestore();
  const student=env.authenticatedContext('student',{student_enrolled:true,email_verified:true}).firestore();
  await assertFails(updateDoc(doc(coordinator,'requirements/r'),archiveFields()));
  await assertFails(updateDoc(doc(admin,'requirements/r'),{...archiveFields(),storagePath:'student/requirements/replacement.pdf'}));
  await assertFails(setDoc(doc(student,'requirement_versions','new'),{requirementId:'r',version:2}));
  const batch=writeBatch(admin);
  for(const [path] of immutable) batch.update(doc(admin,path),{
    ...archiveFields(), ...(path.startsWith('internship_profiles/') && {status:'Archived'}),
  });
  await assertSucceeds(batch.commit());
  const summary=doc(admin,'academic_archives',year);
  await assertSucceeds(setDoc(summary,{academicYear:year,createdBy:'admin',createdAt:serverTimestamp()}));
  await assertFails(deleteDoc(summary));
  for(const [path] of immutable) {
    assert.equal((await assertSucceeds(getDoc(doc(coordinator,path)))).get('archived'),true);
    await assertFails(getDoc(doc(other,path)));
    for(const actor of [admin,coordinator,student]) {
      await assertFails(updateDoc(doc(actor,path),{archived:false}));
      await assertFails(updateDoc(doc(actor,path),{status:'pending'}));
      await assertFails(deleteDoc(doc(actor,path)));
    }
  }
  for(const actor of [admin,coordinator,student]) {
    await assertSucceeds(getDoc(doc(actor,'requirement_versions/previous')));
    await assertFails(updateDoc(doc(actor,'requirement_versions/previous'),{remarks:'changed'}));
    await assertFails(deleteDoc(doc(actor,'requirement_versions/previous')));
  }
  console.log('PASS archive transition, scoped retrieval, archived record locks and version preservation');
} finally {
  await env.cleanup();
}
