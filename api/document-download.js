import { createDocumentDownload } from '../tools/document_download_core.mjs';

export default async function handler(req, res) {
  const origin = process.env.APP_ORIGIN?.trim();
  if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed.' });
  const result = await createDocumentDownload({ authorization: req.headers.authorization, body: req.body });
  return res.status(result.status).json(result.payload);
}
