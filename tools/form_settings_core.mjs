import { getAuth } from 'firebase-admin/auth';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { canonicalCasProgram, coordinatorProgram } from './cas_programs.mjs';
import { checkPdf, documentBucket, invalid, readStoredFile } from './private_files.mjs';
import { ensureAdminApp } from './staff_claims_core.mjs';

const settings = (db, kind) => db.collection('form_settings').doc(kind);
const maxPdfBytes = 5 * 1024 * 1024;

export function isTemplatePath(path, owner) {
  if (typeof path !== 'string' || path.length > 1024) return false;
  const parts = path.split('/');
  return parts.length === 3 &&
    /^[^%\\\x00-\x1f/]+$/.test(parts[0]) &&
    parts[0] !== '.' && parts[0] !== '..' &&
    (owner === undefined || parts[0] === owner) &&
    parts[1] === 'form_templates' &&
    /^[a-zA-Z0-9._-]+[.]pdf$/i.test(parts[2]);
}

export async function readDefaultTemplate(db, kind) {
  const data = (await settings(db, kind).get()).data();
  return isTemplatePath(data?.path) && typeof data?.name === 'string'
    ? { path: data.path, name: data.name }
    : null;
}

export async function inspectEvaluationTemplate(bytes) {
  const official = await checkPdf(bytes);
  const fields = official.getForm().getFields().filter(field => !field.isReadOnly());
  if (!fields.length) throw invalid('The official evaluation PDF must have editable form fields.');
  return { official, fields };
}

export async function handleFormSettings({ authorization, body }, dependencies = {}) {
  const token = /^Bearer (\S+)$/i.exec(authorization ?? '')?.[1];
  if (!token) throw invalid('Staff sign-in is required.', 401);
  if (!dependencies.auth || !dependencies.db) ensureAdminApp();
  const auth = dependencies.auth ?? getAuth();
  const db = dependencies.db ?? getFirestore();
  let identity;
  try {
    identity = await auth.verifyIdToken(token, true);
  } catch {
    throw invalid('Sign in again to manage school forms.', 401);
  }
  const actorRef = db.collection('users').doc(identity.uid);
  const actor = (await actorRef.get()).data();
  const isAdmin = actor?.role === 'admin';
  const isCoordinator = actor?.role === 'coordinator' && actor.approvalStatus === 'approved';
  if (actor?.active !== true || (!isAdmin && !isCoordinator)) {
    throw invalid('Only authorized staff can access school form settings.', 403);
  }
  let input;
  try {
    input = typeof body === 'string' ? JSON.parse(body) : body;
  } catch {
    throw invalid('Invalid form settings request.');
  }
  if (input?.action === 'remove-requirement') {
    const id = input.id;
    if (typeof id !== 'string' || !id || id.length > 160 || /[/\\]/.test(id)) {
      throw invalid('Choose a requirement bin.');
    }
    const ref = db.collection('requirement_definitions').doc(id);
    await db.runTransaction(async tx => {
      const currentActor = (await tx.get(actorRef)).data();
      if (currentActor?.active !== true ||
          (currentActor.role !== 'admin' &&
           !(currentActor.role === 'coordinator' && currentActor.approvalStatus === 'approved'))) {
        throw invalid('Only authorized staff can remove requirement bins.', 403);
      }
      const definition = (await tx.get(ref)).data();
      if (!definition) throw invalid('The requirement bin was not found.', 404);
      if (currentActor.role !== 'admin') {
        const program = coordinatorProgram(currentActor);
        if (!program || canonicalCasProgram(definition.program) !== program) {
          throw invalid('Program Coordinators can remove bins for their own program. Ask the college administrator to remove college-wide bins.', 403);
        }
      }
      if (definition.active === false) return;
      tx.update(ref, {
        active: false,
        updatedBy: identity.uid,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(db.collection('activity_logs').doc(), {
        userId: identity.uid,
        userName: currentActor.displayName ?? '',
        action: `Removed requirement bin: ${definition.title}`,
        createdAt: FieldValue.serverTimestamp(),
      });
    });
    return { ok: true };
  }

  const kind = input?.kind;
  if (!['moa', 'evaluation'].includes(kind)) throw invalid('Choose a template type.');
  if (input.action === 'get-default') return { template: await readDefaultTemplate(db, kind) };
  if (input.action !== 'set-default' && input.action !== 'clear-default') {
    throw invalid('Invalid form settings action.');
  }
  if (!isAdmin) throw invalid('Only the college administrator can change default templates.', 403);
  const ref = settings(db, kind);
  if (input.action === 'clear-default') {
    await ref.delete();
    return { template: null };
  }
  const { path, name } = input;
  if (!isTemplatePath(path, identity.uid) || typeof name !== 'string' ||
      name.length > 240 || !name.toLowerCase().endsWith('.pdf')) {
    throw invalid('Choose a PDF to use as the default.');
  }
  const bytes = await (dependencies.readFile ?? readStoredFile)(documentBucket(), path, maxPdfBytes);
  if (kind === 'evaluation') await inspectEvaluationTemplate(bytes);
  else await checkPdf(bytes);
  const template = { path, name };
  await ref.set({ ...template, updatedBy: identity.uid, updatedAt: FieldValue.serverTimestamp() });
  return { template };
}
