export function singleMailbox(value) {
  return typeof value === 'string' && /^[^\s<>,;@]+@[^\s<>,;@]+\.[^\s<>,;@]+$/.test(value);
}

export async function sendSchoolEmail({ to, subject, text }) {
  if (!singleMailbox(to)) throw new Error('A single valid recipient address is required.');
  const key = process.env.RESEND_API_KEY;
  const from = process.env.SCHOOL_EMAIL_FROM;
  if (!key || !from) throw new Error('School email delivery is not configured.');
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from, to: [to], subject, text }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) {
    const { name } = (await response.json().catch(() => null)) ?? {};
    const reason = typeof name === 'string' && /^[a-z_]{1,64}$/.test(name) ? ' (' + name + ')' : '';
    const hint = response.status === 403 && from === 'onboarding@resend.dev'
      ? ' Use the Resend account inbox for the test sender, or use a verified sending domain.'
      : ' Check the failed request in the Resend Logs dashboard.';
    throw new Error('Resend rejected the email with HTTP ' + response.status + reason + '.' + hint);
  }
}
