import { handleFormSettings } from '../tools/form_settings_core.mjs';

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  const origin = process.env.APP_ORIGIN?.trim();
  if (origin) res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed.' });
  try {
    const payload = await handleFormSettings({ authorization: req.headers.authorization, body: req.body });
    return res.status(200).json(payload);
  } catch (error) {
    return res.status(error.httpStatus || 500).json({
      error: error.httpStatus ? error.message : 'The form settings could not be saved or loaded.',
    });
  }
}
