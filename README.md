# PracticumConnect

## Student invitations

The CAS College Coordinator can use **Add student** in **Internship Records**
to enter a full name, student number, and email address and send one invitation.
Use **Import official roster** for a batch of JSON entries. A pending invitation
can be resent from the student's row.

## Firebase for student invitations

Set `STUDENT_EMAIL_PROVIDER=firebase` in the Vercel environment used by the app
and redeploy. This uses the existing Firebase Admin connection to send the
Firebase Authentication password reset template as the student's password setup
email. Set `APP_ORIGIN` to the public HTTPS app URL and add its hostname in
Firebase Authentication **Settings → Authorized domains** so the student can
return to the app after setting their password. The Firebase Admin credential
uses the `firebaseauth.users.sendEmail` permission.

## Gmail app password for student invitations

To send invitations from Gmail without a custom domain, turn on 2-Step
Verification for the sender account and create a
[Google app password](https://support.google.com/mail/answer/185833). Add these
server-side environment variables to the Vercel environment you deploy to, then
redeploy.

| Variable | Value |
| --- | --- |
| `STUDENT_EMAIL_PROVIDER` | `gmail_smtp` |
| `GMAIL_SMTP_USER` | The full Gmail address of the sender |
| `GMAIL_SMTP_APP_PASSWORD` | The app password, stored as a Vercel secret |
| `APP_ORIGIN` | The public HTTPS URL students should open, such as the Vercel deployment alias |

Firebase issues the password setup link included in the invitation and sends
the email verification message when an unverified student first signs in.

## Gmail API for student invitations

Roster imports and **Resend activation email** can send from
`connectpracticum@gmail.com` through the Gmail API. Set up the sender once:

1. In Google Cloud, enable the [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com).
   Set the Google Auth Platform audience to External and add
   `connectpracticum@gmail.com` as a test user while the app is in Testing.
2. Create a **Web application** OAuth client and add
   `https://developers.google.com/oauthplayground` as an authorized redirect URI.
3. In [Google OAuth Playground](https://developers.google.com/oauthplayground/),
   open settings and select **Use your own OAuth credentials**. Enter the
   client ID and secret. Authorize only `https://www.googleapis.com/auth/gmail.send`
   while signed in as `connectpracticum@gmail.com`, then exchange the code
   for tokens.
4. In Vercel, set these variables for **Preview** and redeploy `vercel-preview`.
   Enter the credentials directly in Vercel.

   | Variable | Value |
   | --- | --- |
   | `STUDENT_EMAIL_PROVIDER` | `gmail` |
   | `GMAIL_CLIENT_ID` | Web OAuth client ID |
   | `GMAIL_CLIENT_SECRET` | Web OAuth client secret |
   | `GMAIL_REFRESH_TOKEN` | Refresh token from the authorized Gmail mailbox |

   Keep `APP_ORIGIN` set to the app URL students should open. Once deployed,
   retry a pending student's activation email from Student Internship Records.

Google-issued refresh tokens for External apps in Testing expire after seven
days for Gmail scopes. Reauthorize and update the token when it expires, or
follow [Google's OAuth publishing guidance](https://developers.google.com/identity/protocols/oauth2/production-readiness/policy-compliance)
for ongoing use.

With `STUDENT_EMAIL_PROVIDER` unset, the student flow uses Resend. Evaluation
emails continue to use their existing Resend settings.
