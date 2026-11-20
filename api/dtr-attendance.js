import { handleDtrAttendance } from '../tools/dtr_attendance_core.mjs';

export default async function handler(req, res) {
  const allowedOrigin = process.env.APP_ORIGIN?.trim();
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Vary', 'Origin');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed.' });
  const result = await handleDtrAttendance({ authorization: req.headers.authorization, body: req.body });
  return res.status(result.status).json(result.payload);
}
