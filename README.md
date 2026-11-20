# PracticumConnect

## Gmail for student invitations

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
