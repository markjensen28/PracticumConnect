import assert from 'node:assert/strict';
import { sendEvaluationMail, verifyPublicEvaluationAccess } from './evaluation_core.mjs';

export async function mailboxProof(token, email) {
  let code;
  const sent = await sendEvaluationMail({ body: { action: 'requestCode', token, email } }, async (mail) => {
    assert.equal(mail.to, email);
    code = mail.text.match(/code is ([A-F0-9]{12})/)[1];
  });
  assert.equal(sent.status, 200);
  const body = { token, email, code };
  assert.equal((await verifyPublicEvaluationAccess({ body: { ...body, code: 'incorrect' } })).status, 403);
  const verified = await verifyPublicEvaluationAccess({ body });
  assert.equal(verified.status, 200);
  assert.equal((await verifyPublicEvaluationAccess({ body })).status, 403);
  return verified.payload.proof;
}
