import nodemailer from 'nodemailer';

export function singleMailbox(value) {
  return typeof value === 'string' && /^[^\s<>,;@]+@[^\s<>,;@]+\.[^\s<>,;@]+$/.test(value);
}

function gmailCredentials() {
  return {
    client_id: process.env.GMAIL_CLIENT_ID?.trim(),
    client_secret: process.env.GMAIL_CLIENT_SECRET?.trim(),
    refresh_token: process.env.GMAIL_REFRESH_TOKEN?.trim(),
  };
}

function gmailSmtpCredentials() {
  return {
    user: process.env.GMAIL_SMTP_USER?.trim(),
    pass: process.env.GMAIL_SMTP_APP_PASSWORD?.replace(/\s+/g, ''),
  };
}

function studentEmailProvider() {
  return process.env.STUDENT_EMAIL_PROVIDER?.trim() || 'resend';
}

export function studentEmailConfigured() {
  const provider = studentEmailProvider();
  if (provider === 'gmail') return Object.values(gmailCredentials()).every(Boolean);
  if (provider === 'gmail_smtp') {
    const { user, pass } = gmailSmtpCredentials();
    return singleMailbox(user) && /^[a-z0-9]{16}$/i.test(pass ?? '');
  }
  return provider === 'resend' && Boolean(process.env.RESEND_API_KEY && process.env.SCHOOL_EMAIL_FROM);
}

export async function sendStudentEmail(message) {
  if (!studentEmailConfigured()) throw new Error('Student email delivery is not configured.');
  const provider = studentEmailProvider();
  if (provider === 'resend') return sendSchoolEmail(message);

  const { to, subject, text } = message;
  if (!singleMailbox(to)) throw new Error('A single valid recipient address is required.');
  if (!/^[\x20-\x7e]{1,200}$/.test(subject)) throw new Error('Invalid invitation subject.');
  if (provider === 'gmail_smtp') {
    const auth = gmailSmtpCredentials();
    const transport = nodemailer.createTransport({
      host: 'smtp.gmail.com',
      port: 465,
      secure: true,
      auth,
      connectionTimeout: 8000,
      greetingTimeout: 8000,
      socketTimeout: 12000,
    });
    try {
      const result = await transport.sendMail({
        from: { name: 'Practicum Connect', address: auth.user },
        to,
        subject,
        text,
      });
      if (!result.accepted.length) throw new Error('Recipient rejected.');
    } catch (error) {
      if (error.code === 'EAUTH') {
        throw new Error('Gmail refused the sign-in. Check the sender address and Gmail app password.');
      }
      throw new Error('Gmail could not send the invitation. Try again from the pending student record.');
    }
    return;
  }

  const authorization = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({ ...gmailCredentials(), grant_type: 'refresh_token' }),
    signal: AbortSignal.timeout(8000),
  });
  const { access_token: accessToken } = (await authorization.json().catch(() => null)) ?? {};
  if (!authorization.ok || typeof accessToken !== 'string' || !accessToken) {
    throw new Error('Gmail authorization failed. Check the OAuth credentials and reauthorize the sender if needed.');
  }

  const encodedText = Buffer.from(text, 'utf8').toString('base64');
  const mime = [
    'From: Practicum Connect <connectpracticum@gmail.com>',
    `To: ${to}`,
    `Subject: ${subject}`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    ...(encodedText.match(/.{1,76}/g) ?? []),
    '',
  ].join('\r\n');
  const response = await fetch('https://gmail.googleapis.com/gmail/v1/users/me/messages/send', {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ raw: Buffer.from(mime, 'utf8').toString('base64url') }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) {
    throw new Error(`Gmail rejected the invitation (HTTP ${response.status}). Check that the Gmail API is enabled and the mailbox granted permission to send.`);
  }
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
