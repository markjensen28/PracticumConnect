import { PDFDocument } from 'pdf-lib';

export const documentBucket = () => process.env.SUPABASE_BUCKET || 'PracticumConnectStorage';
export const evaluationBucket = 'practicum-evaluations';
export function invalid(message, status = 400) {
  return Object.assign(new Error(message), { httpStatus: status });
}

export async function storageRequest(route, bucket, path, options = {}) {
  const base = process.env.SUPABASE_URL?.replace(/\/$/, '');
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!base || !key) throw invalid('Private file storage is not configured.', 503);
  const object = [bucket, ...path.split('/')].map(encodeURIComponent).join('/');
  const result = await fetch(`${base}/storage/v1/object${route}/${object}`, {
    ...options,
    headers: { Authorization: `Bearer ${key}`, apikey: key, ...options.headers },
  });
  if (!result.ok) {
    await result.body?.cancel();
    throw invalid('The private file could not be accessed. Check the upload and try again.', 400);
  }
  return result;
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
  return process.env.SUPABASE_URL.replace(/\/$/, '') + '/storage/v1' + relative;
}
