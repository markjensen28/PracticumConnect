import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createDocumentDownload } from './document_download_core.mjs';

const coordinator = { role: 'coordinator', active: true, approvalStatus: 'approved' };
function fixture(actor = coordinator, owner = { role: 'student', coordinatorId: 'staff' }) {
  const calls = [];
  return {
    calls,
    auth: { verifyIdToken: async (token, revoked) => { assert.equal(revoked, true); return { uid: 'staff' }; } },
    db: { collection: () => ({ doc: id => ({ get: async () => ({ data: () => id === 'staff' ? actor : owner }) }) }) },
    config: { SUPABASE_URL: 'https://storage.example', SUPABASE_SERVICE_ROLE_KEY: 'server-only' },
    fetch: async (url, options) => {
      calls.push({ url, options });
      return { ok: true, json: async () => ({ signedURL: '/object/sign/bucket/file?token=test' }) };
    },
  };
}
const request = { authorization: 'Bearer test', body: { path: 'student/requirements/file.pdf' } };
test('assigned coordinator receives a five-minute signed URL', async () => {
  const deps = fixture();
  const result = await createDocumentDownload(request, deps);
  assert.equal(result.status, 200);
  assert.equal(result.payload.url, 'https://storage.example/storage/v1/object/sign/bucket/file?token=test');
  assert.equal(JSON.parse(deps.calls[0].options.body).expiresIn, 300);
});
for (const [name, actor, owner] of [
  ['unassigned coordinator', coordinator, { role: 'student', coordinatorId: 'other' }],
  ['reassigned student', coordinator, { role: 'student', coordinatorId: 'new-staff' }],
  ['inactive coordinator', { ...coordinator, active: false }],
  ['pending coordinator', { ...coordinator, approvalStatus: 'pending' }],
  ['student reading another student', { role: 'student', active: true }],
  ['missing owner', coordinator, null],
]) test(name + ' cannot sign or reach storage', async () => {
  const deps = fixture(actor, owner);
  assert.equal((await createDocumentDownload(request, deps)).status, 403);
  assert.equal(deps.calls.length, 0);
});
test('admin access remains available', async () => {
  assert.equal((await createDocumentDownload(request, fixture({ role: 'admin', active: true }))).status, 200);
});
for (const path of ['student/../file.pdf', 'student/requirements/%2e%2e', 'student/requirements/a/b', 'student/moas/file']) {
  test('rejects unauthorized or malformed path: ' + path, async () => {
    const deps = fixture();
    assert.notEqual((await createDocumentDownload({ ...request, body: { path } }, deps)).status, 200);
    assert.equal(deps.calls.length, 0);
  });
}
test('missing or invalid authentication is rejected', async () => {
  assert.equal((await createDocumentDownload({ body: request.body }, fixture())).status, 401);
  const deps = fixture(); deps.auth.verifyIdToken = async () => { throw Error('invalid'); };
  assert.equal((await createDocumentDownload(request, deps)).status, 401);
  assert.equal(deps.calls.length, 0);
});
