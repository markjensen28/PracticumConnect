import { PDFDocument } from 'pdf-lib';

export const documentBucket = () => process.env.SUPABASE_BUCKET?.trim() || 'PracticumConnectStorage';
export const evaluationBucket = 'practicum-evaluations';
export function invalid(message, status = 400) {
  return Object.assign(new Error(message), { httpStatus: status });
}

async function requestStorage(endpoint, options = {}) {
  const base = process.env.SUPABASE_URL?.trim().replace(/\/$/, '');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!base || !key) throw invalid('Private file storage is not configured.', 503);
  const result = await fetch(`${base}/storage/v1${endpoint}`, {
    ...options,
    headers: { Authorization: `Bearer ${key}`, apikey: key, ...options.headers },
  });
  return result;
}

async function storageError(result) {
  const detail = await result.json().catch(() => ({}));
  const code = detail?.code ?? detail?.error;
  const message = typeof detail?.message === 'string' ? detail.message : '';
  const missingBucket = code === 'NoSuchBucket' || /^bucket (not found|does not exist)\.?$/i.test(message);
  return Object.assign(
    invalid('The private file could not be accessed. Check the upload and try again.'),
    { storageStatus: result.status, storageCode: code, missingBucket },
  );
}

export async function storageRequest(route, bucket, path, options = {}) {
  const object = [bucket, ...path.split('/')].map(encodeURIComponent).join('/');
  const result = await requestStorage(`/object${route}/${object}`, options);
  if (!result.ok) throw await storageError(result);
  return result;
}

// The server is the only writer of evaluation copies. A missing bucket can
// occur on a fresh storage project or when production points to a new project.
export async function storeEvaluationTemplate(path, bytes) {
  const upload = () => storageRequest('', evaluationBucket, path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/pdf' },
    body: bytes,
  });
  try {
    return await upload();
  } catch (error) {
    if (!error.missingBucket) throw error;
  }
  const bucket = await requestStorage('/bucket', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: evaluationBucket, name: evaluationBucket, public: false }),
  });
  if (!bucket.ok) {
    const error = await storageError(bucket);
    if (error.storageStatus !== 409 && error.storageCode !== 'BucketAlreadyExists') throw error;
  } else {
    await bucket.body?.cancel();
  }
  return upload();
}

export async function removeStoredFile(bucket, path) {
  const result = await requestStorage(`/object/${encodeURIComponent(bucket)}`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefixes: [path] }),
  });
  if (!result.ok) throw await storageError(result);
  await result.body?.cancel();
}

export async function readStoredFile(bucket, path, limit) {
  const response = await storageRequest('/authenticated', bucket, path);
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > limit) throw invalid('The uploaded file exceeds the size limit.');
    chunks.push(chunk);
  }
  if (!size) throw invalid('The uploaded file is empty.');
  return Buffer.concat(chunks);
}

export async function checkPdf(bytes) {
  try {
    if (bytes.subarray(0, 5).toString() !== '%PDF-') throw new Error();
    const doc = await PDFDocument.load(bytes, { throwOnInvalidObject: true });
    if (!doc.getPageCount()) throw new Error();
    return doc;
  } catch {
    throw invalid('Choose a readable, unencrypted PDF.');
  }
}

export async function signedFileUrl(path, upload = false) {
  const response = await storageRequest(upload ? '/upload/sign' : '/sign', evaluationBucket, path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(upload ? {} : { expiresIn: 300 }),
  });
  const data = await response.json();
  const relative = upload ? data.url : data.signedURL;
  if (!relative?.startsWith('/object/')) throw invalid('Unable to prepare the private file link.', 502);
  return process.env.SUPABASE_URL.trim().replace(/\/$/, '') + '/storage/v1' + relative;
}
