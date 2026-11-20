Supervisor evaluation and document submission

Issue new invitations with the approved blank editable PDF. Each invitation
has its own private copy. After mailbox verification the supervisor downloads
the form, selects and previews a completed PDF (up to 10 MB), then confirms
the upload and final submission.
Staff open the completed file in Evaluations. Older invitations retain their
original ratings workflow and historical scores.

Deploy the updated API and Flutter client, apply supabase_storage_policies.sql
(including the private practicum-evaluations bucket), and publish firestore.rules
and the updated completion function together. Configure SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY on the backend. The service key is server-only.
Requirement creation and revision now use /api/requirement-submit.

DTR update (shift-based attendance)
  - Students sign in using the camera; the API records the server timestamp.
  - Sign Out is available at the placement's scheduled shift end. Breaks are
    included in the scheduled shift for now.
  - A coordinator can resolve a forgotten or early Sign Out with a written reason.
  - Check-in photos stay in the private PracticumConnectStorage bucket.
  - Configure shift start/end, work days, and IANA time zone in the student's
    Internship Profile before the student attempts Sign In.
  - Local DTR actions use the API at localhost:8787. Start it with:
      node tools/approval_server.mjs
    The DTR backend includes the operating system's trusted certificates on
    Node.js 22.19+ or 24.5+ while keeping TLS verification enabled. Older Node.js
    versions that support it can use node --use-system-ca tools/approval_server.mjs.
    It reads the ignored config/local.json for the Supabase project URL and
    publishable key. Firebase Admin credentials are still required by the local
    API (Application Default Credentials or the existing FIREBASE_* settings).
  - Deploy firestore.rules and the api/dtr-attendance.js Vercel route before using
    the flow in a hosted build. Vercel already needs SUPABASE_URL and
    SUPABASE_PUBLISHABLE_KEY for its Flutter build; Firebase Admin credentials
    must also be configured for server routes.

After copying the file into your project, run:
  dart format .\lib\screens\public_evaluation_screen.dart
  flutter analyze
  flutter test
  flutter run -d chrome --dart-define-from-file=config/local.json

Automated in-app reminders and requirement compliance

Deploy the Firebase Functions package (including the reminder triggers and
scheduled reconciliation), firestore.rules, and the Flutter client together.
Enable Cloud Scheduler for the daily recovery scan. Changes to assignments,
submissions, accounts, or preferences schedule or cancel in-app notices.
An open inbox shows a scheduled notice when its time arrives.

In Settings, students choose how many hours or days before the deadline to
receive a reminder. Assigned program coordinators choose how long a submission
may await verification before a reminder appears. Defaults are 3 days before
and 2 days after, respectively. Choices range from 1 hour to 30 days.
Date-only deadlines end at 23:59 Asia/Manila. Saving a preference updates
upcoming notices. Already delivered notices are retained.

Dashboard and Student Summary compliance count verified, distinct requirements
against the active definitions for the student's program and academic year.
Definitions currently apply across years. Only submissions from the student's
current academic year count. The date filter limits submitted-record counts;
the current compliance figure also includes work outside that date range.
