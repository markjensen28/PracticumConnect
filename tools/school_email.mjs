import { isIP } from 'node:net';
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

function emailProviderConfigured(provider) {
  if (provider === 'firebase') return true;
  if (provider === 'gmail') return Object.values(gmailCredentials()).every(Boolean);
  if (provider === 'gmail_smtp') {
    const { user, pass } = gmailSmtpCredentials();
    return singleMailbox(user) && /^[a-z0-9]{16}$/i.test(pass ?? '');
  }
  return provider === 'resend' && Boolean(process.env.RESEND_API_KEY && process.env.SCHOOL_EMAIL_FROM);
}

export function studentEmailConfigured() {
  return emailProviderConfigured(studentEmailProvider());
}

function evaluationEmailProvider() {
  const configured = process.env.EVALUATION_EMAIL_PROVIDER?.trim();
  if (configured) return configured;
  const studentProvider = studentEmailProvider();
  if (studentProvider !== 'firebase') return studentProvider;
  return ['resend', 'gmail', 'gmail_smtp'].find(emailProviderConfigured) || 'resend';
}

export function evaluationEmailConfigured() {
  const provider = evaluationEmailProvider();
  return provider !== 'firebase' && emailProviderConfigured(provider);
}

export async function sendEvaluationEmail(message) {
  if (!evaluationEmailConfigured()) throw new Error('Supervisor email delivery is not configured.');
  return sendMessageWithProvider(evaluationEmailProvider(), message);
}

export async function sendStudentInvitation({ to, displayName, auth, requesterIp }) {
  if (studentEmailProvider() === 'firebase') {
    return sendStudentEmail({ to, auth, requesterIp });
  }

  const link = await auth.generatePasswordResetLink(to);
  return sendStudentEmail({
    to,
    subject: 'Activate your Practicum Connect student account',
    text: `Hello ${displayName},\n\nYour school has enrolled you in Practicum Connect. Set your password using the private Firebase link below, then sign in with this address at ${process.env.APP_ORIGIN}. If prompted, verify your email before signing in again.\n\n${link}`,
  });
}

export async function sendStudentEmail(message) {
  if (!studentEmailConfigured()) throw new Error('Student email delivery is not configured.');
  const provider = studentEmailProvider();
  if (provider === 'firebase') {
    if (!singleMailbox(message.to)) throw new Error('A single valid recipient address is required.');
    return sendFirebasePasswordResetEmail(message);
  }
  return sendMessageWithProvider(provider, message);
}

async function sendMessageWithProvider(provider, message) {
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
      throw new Error('Gmail could not send the email. Try again.');
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

async function sendFirebasePasswordResetEmail({ to, auth, requesterIp }) {
  const options = auth?.app?.options;
  const projectId = options?.projectId ?? process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT;
  if (!projectId || !options?.credential) {
    throw new Error('Set FIREBASE_PROJECT_ID for the Firebase Admin connection used to send invitations.');
  }

  const token = await options.credential.getAccessToken().catch(() => null);
  if (!token?.access_token) throw new Error('Firebase Admin could not authorize the invitation request.');

  const userIp = typeof requesterIp === 'string' ? requesterIp.trim() : '';
  const endpoint = `https://identitytoolkit.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/accounts:sendOobCode`;
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      requestType: 'PASSWORD_RESET',
      email: to,
      continueUrl: process.env.APP_ORIGIN?.trim(),
      returnOobLink: false,
      ...(isIP(userIp) ? { userIp } : {}),
    }),
    signal: AbortSignal.timeout(12000),
  });
  if (response.ok) return;

  const { error } = (await response.json().catch(() => null)) ?? {};
  const code = error?.message?.split(':')[0];
  if (code === 'UNAUTHORIZED_DOMAIN' || code === 'INVALID_CONTINUE_URI') {
    throw new Error('Add the APP_ORIGIN hostname to Firebase Authentication’s Authorized domains.');
  }
  if (response.status === 401 || response.status === 403) {
    throw new Error('The Firebase Admin connection could not send email. Check its firebaseauth.users.sendEmail permission.');
  }
  if (response.status === 429 || code === 'TOO_MANY_ATTEMPTS_TRY_LATER' || code === 'QUOTA_EXCEEDED') {
    throw new Error('Firebase is limiting password setup emails. Retry from the pending student record later.');
  }
  throw new Error(`Firebase could not send the password setup email (HTTP ${response.status}). Retry from the pending student record.`);
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
