import { handleEvaluationAction, getPublicEvaluation } from '../tools/evaluation_core.mjs';

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  const allowedOrigin = process.env.APP_ORIGIN?.trim();
  if (allowedOrigin) res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Vary', 'Origin');

  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }

  try {
    let result;
    if (req.method === 'GET') {
      result = await getPublicEvaluation({ token: req.query?.token });
    } else if (req.method === 'POST') {
      result = await handleEvaluationAction({ authorization: req.headers.authorization, body: req.body });
    } else {
      result = { status: 405, payload: { error: 'Method not allowed.' } };
    }
    res.status(result.status).json(result.payload);
  } catch (error) {
    res.status(error.httpStatus || 500).json({
      error: error instanceof Error ? error.message : String(error),
    });
  }
}
