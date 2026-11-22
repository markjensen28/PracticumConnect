import { importOfficialRoster } from '../tools/official_roster_api.mjs';
export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') return res.status(405).end();
  const result = await importOfficialRoster({
    authorization: req.headers.authorization,
    body: req.body,
    requesterIp: req.headers['x-vercel-forwarded-for'] ?? req.socket?.remoteAddress,
  });
  return res.status(result.status).json(result.payload);
}
