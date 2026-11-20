import { validAcademicYear } from '../functions/attendance.mjs';
﻿import { createHash } from 'node:crypto';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { ensureAdminApp } from './staff_claims_core.mjs';
import { documentBucket, invalid, readStoredFile, checkPdf } from './private_files.mjs';

export async function verifyRequirementFile(name, bytes) {
  const extension = name.split('.').pop().toLowerCase();
  if (extension === 'pdf') return checkPdf(bytes);
  const signatures = {
    png: '89504e470d0a1a0a',
    jpg: 'ffd8ff',
    jpeg: 'ffd8ff',
    doc: 'd0cf11e0a1b11ae1',
    docx: '504b0304',
  };
  const signature = signatures[extension];
  if (
    !signature ||
    !bytes.subarray(0, 8).toString('hex').startsWith(signature) ||
    (extension === 'docx' && !bytes.includes(Buffer.from('word/document.xml')))
  ) {
    throw invalid('Choose a PDF, Word document, PNG or JPEG matching its file type.');
  }
}

function documentId(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 250 && !/[/]/.test(value);
}

export async function finalizeRequirement({ authorization, body }) {
  try {
    ensureAdminApp();
    const bearer = /^Bearer (\S+)$/i.exec(authorization || '')?.[1];
    if (!bearer) throw invalid('Sign in before submitting.', 401);
    const account = await getAuth()
      .verifyIdToken(bearer, true)
      .catch(() => {
        throw invalid('Sign in again.', 401);
      });
    if (!account.student_enrolled || !account.email_verified)
      throw invalid('Activate your student account.', 403);
    const input = typeof body === 'string' ? JSON.parse(body) : body;
    const { fileName, storagePath, definitionId, requirementId, expectedVersion } = input || {};
    if (
      !documentId(definitionId) ||
      (requirementId != null && !documentId(requirementId)) ||
      typeof fileName !== 'string' ||
      !fileName.trim() ||
      fileName.length > 255 ||
      /[\\/]/.test(fileName)
    ) {
      throw invalid('Select an assigned requirement and a file.');
    }
    const prefix = account.uid + '/requirements/';
    const safeName = fileName.replace(/[^A-Za-z0-9._-]/g, '_');
    if (
      typeof storagePath !== 'string' ||
      !storagePath.startsWith(prefix) ||
      !/^\d+_/.test(storagePath.slice(prefix.length)) ||
      storagePath.slice(prefix.length).replace(/^\d+_/, '') !== safeName
    )
      throw invalid('Invalid submission file path.');
    const db = getFirestore();
    const profile = (await db.collection('users').doc(account.uid).get()).data();
    if (!profile?.active || profile.role !== 'student' || profile.enrollmentStatus !== 'active') {
      throw invalid('Active enrollment required.', 403);
    }
    const bytes = await readStoredFile(documentBucket(), storagePath, 5 * 1024 * 1024);
    await verifyRequirementFile(fileName, bytes);
    const id = await db.runTransaction(async (tx) => {
      const user = (await tx.get(db.collection('users').doc(account.uid))).data();
      if (!user?.active || user.role !== 'student' || user.enrollmentStatus !== 'active')
        throw invalid('Active enrollment required.', 403);
      if (!user.coordinatorId || !validAcademicYear(user.academicYear))
        throw invalid('Ask your coordinator to assign your academic year (YYYY-YYYY) and coordinator first.');
      const placement = await tx.get(db.collection('internship_profiles').doc(account.uid));
      if (placement.get('archived') === true && placement.get('academicYear') === user.academicYear) {
        throw invalid('This internship has been archived.', 409);
      }
      const definition = (
        await tx.get(db.collection('requirement_definitions').doc(definitionId))
      ).data();
      if (
        !definition?.title?.trim() ||
        definition.active === false ||
        (definition.program?.trim() &&
          definition.program !== 'All Programs' &&
          definition.program !== user.program)
      ) {
        throw invalid('This requirement is unavailable for your program.');
      }
      const matchesDefinition = (record) => record.definitionId
        ? record.definitionId === definitionId
        : typeof record.title === 'string' && record.title.trim().toLowerCase() === definition.title.trim().toLowerCase();
      const key = createHash('sha256')
        .update(JSON.stringify([account.uid, user.academicYear, definitionId]))
        .digest('hex');
      const ref = db.collection('requirements').doc(requirementId || key);
      const old = (await tx.get(ref)).data();
      if (
        old &&
        (old.studentId !== account.uid ||
          old.academicYear !== user.academicYear ||
          old.archived ||
          !matchesDefinition(old))
      ) {
        throw invalid('This submission does not match the assigned requirement.', 403);
      }
      if (old?.storagePath === storagePath) return ref.id;
      if (
        requirementId &&
        (!old ||
          !['needs_revision', 'rejected'].includes(old.status) ||
          (old.version ?? 1) !== expectedVersion)
      ) {
        throw invalid('Refresh the requirement before submitting a revision.', 409);
      }
      if (!requirementId) {
        const previous = await tx.get(
          db.collection('requirements').where('studentId', '==', account.uid),
        );
        if (
          old ||
          previous.docs.some((doc) => {
            const r = doc.data();
            return (
              !r.archived &&
              r.academicYear === user.academicYear &&
              matchesDefinition(r)
            );
          })
        )
          throw invalid('This requirement already has a submission. Open its current record.', 409);
      }
      const stamp = FieldValue.serverTimestamp();
      const priorVersion = old?.version ?? 1;
      if (old && (!Number.isSafeInteger(priorVersion) || priorVersion < 1)) {
        throw invalid('Ask your coordinator to reconcile the prior revision number.', 409);
      }
      if (old) {
        tx.create(db.collection('requirement_versions').doc(ref.id + '_' + priorVersion), {
          requirementId: ref.id,
          version: priorVersion,
          fileName: old.fileName ?? null,
          storagePath: old.storagePath ?? null,
          submittedAt: old.submittedAt ?? null,
          status: old.status,
          remarks: old.remarks ?? null,
          reviewedBy: old.reviewedBy ?? null,
          reviewedAt: old.reviewedAt ?? null,
          createdAt: stamp,
        });
      }
      tx.set(
        ref,
        {
          studentId: account.uid,
          studentName: user.displayName || '',
          studentNumber: user.studentNumber ?? null,
          coordinatorId: user.coordinatorId,
          academicYear: user.academicYear,
          program: user.program ?? null,
          definitionId,
          title: definition.title,
          category: definition.category || 'General',
          dueDate: definition.dueDate ?? null,
          version: old ? priorVersion + 1 : 1,
          reviewedBy: null,
          reviewedAt: null,
          status: 'pending',
          archived: false,
          remarks: null,
          storagePath,
          fileName,
          submittedAt: stamp,
          updatedAt: stamp,
        },
        { merge: true },
      );
      return ref.id;
    });
    return { status: 200, payload: { id } };
  } catch (error) {
    return {
      status: error.httpStatus || 500,
      payload: { error: error.httpStatus ? error.message : 'Unable to finalize this requirement.' },
    };
  }
}
