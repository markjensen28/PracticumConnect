# First three blocking/high-priority findings

All three findings were still present in the working tree reviewed on 18 November 2026.

1. **Coordinator storage access:** Supabase no longer grants coordinators bucket-wide SELECT access. Cross-user downloads use `POST /api/document-download`, verify the Firebase ID token (including revocation), check the active/approved Firestore account and the student's current `coordinatorId`, then issue a five-minute signed URL. Coordinators may access assigned students' requirements and attendance photos. Owners, administrators, and shared blank templates retain their intended access.
2. **File preservation:** Student uploads are append-only. UPDATE and DELETE policies no longer allow students to overwrite or remove objects, including approved files and historical versions. Existing uploads already use unique paths with `upsert: false`; corrections continue through the rejected/needs-revision resubmission workflow. Firestore also rejects resubmission of archived requirements. Submitted document versions and check-in photos are retained for all application roles. Administrators can still remove MOA files and form templates.
3. **Review/status synchronization:** Requirement and DTR queries now include `coordinatorId` for coordinator actors. Review changes, feedback, derived stage, and audit entries commit in one batch. Stage calculation includes the proposed review or profile changes. Identical review/profile retries avoid duplicate feedback/audit entries. A failed stage read leaves the requested write uncommitted. These batches provide atomic writes, but are not serializable across concurrent independent reviewers.

## Deployment

These are repository changes; no production policies or services were deployed.

1. Configure the API server with the existing Firebase Admin credentials, `SUPABASE_URL`, `SUPABASE_BUCKET` (default `PracticumConnectStorage`), and **server-only** `SUPABASE_SERVICE_ROLE_KEY`. Never put the service-role key in Flutter configuration, browser code, or a committed file.
2. Deploy the API and updated Flutter client together. Local development uses the existing `COORDINATOR_APPROVAL_API_URL` origin; `tools/approval_server.mjs` serves the new download route too.
3. Run `supabase_storage_policies.sql` in the correct Supabase project's SQL editor and deploy the updated `firestore.rules`. Verify there are no additional custom permissive storage policies that grant the removed access.
4. Smoke-test assigned/unassigned coordinator downloads, student upload/resubmission, and requirement/DTR/profile review. Previously issued signed URLs remain usable until their expiration.

## Regression checks

- `node --test tools/document_download_test.mjs`
- With `@electric-sql/pglite` installed: `node tools/storage_policy_test.mjs` checks the SQL against an ephemeral PostgreSQL engine with Supabase-compatible auth/storage schemas.
- `flutter test test/review_workflow_test.dart`
- With Firestore emulator at `127.0.0.1:8080` and Firebase rules test dependencies available: `node tools/coordinator_sync_rules_test.mjs`, plus the existing Firestore and notification rules tests.
- `flutter analyze --no-pub lib test`

The workflow tests can run in an isolated package containing the same repository/model sources when the host lacks the Windows C++ compiler required by the application's PDF native dependency. Such a run validates the service logic, not the full application build.

## Findings 4–6

### Release configuration

The web app and HTTP APIs run on Vercel. Requirement changes also use the Firebase Firestore trigger `syncRequirementStage`. Configure each environment with its own public HTTPS `APP_ORIGIN`, verified school sender in `SCHOOL_EMAIL_FROM`, and server-only `RESEND_API_KEY`. Keep the existing Firebase Admin credentials. Use the same settings for the local API or the administrator CLI when exercising mail delivery. Localhost invitation URLs cannot be opened from another person's computer. Use a staging HTTPS origin for real mailbox testing.

Provision the school sending domain in Resend and complete its DNS verification before sending. Firebase Authentication must support email/password accounts and working password-reset and verification handlers. Delivery acceptance from the provider does not confirm inbox placement. Verify the first staging invitation and code in a school-controlled mailbox.

### Student enrollment and migration

An administrator opens **Internship Records → Import official roster**, selects a JSON list, reviews the count, then confirms the invitations. The web importer previews up to 100 rows per file. Keep student numbers as text to preserve leading zeros. The program, section, academic department and academic year are optional.

```json
[
  {
    "studentNumber": "000123",
    "email": "student@example.invalid",
    "displayName": "Example Student",
    "program": "BS Information Technology",
    "academicYear": "2026-2027",
    "department": "Computing",
    "section": "A"
  }
]
```

For existing accounts, first run `node tools/import_student_roster.mjs roster.json` with credentials for the intended project. This is a read-only preflight. Resolve identity conflicts against the official list. Importing with `--apply --migrate-existing` resets passwords for matched legacy accounts, revokes refresh tokens, and sends new invitations while preserving student UIDs and documents. Use that option only for a reviewed roster during the school's planned migration window. Rerunning an interrupted import resumes pending work. Use `--apply --resend` to reissue outstanding invitations.

Students set their password from the emailed Firebase link and sign in with the roster address. If Firebase still reports an unverified email, the app sends a verification link and requires a fresh sign-in. Active, roster-confirmed users receive the claims required for Firestore and Supabase access. Public student profile creation is denied. The separate pending coordinator request workflow still uses Firebase Auth registration.

### Rollout order

1. Dry-run the official roster against the target Firebase project and resolve conflicts. Accounts missing from the roster will lose student portal access under the new rules. Coordinate the account transition before enforcing them.
2. On staging, deploy the APIs and Flutter client, install the Functions dependencies with `npm ci --prefix functions`, and deploy `functions:syncRequirementStage` and `firestore:rules` to the intended project. Apply `supabase_storage_policies.sql` to its paired Supabase environment. Coordinate these releases during production cutover as well. A Vercel deployment alone omits the trigger and database policies.
3. Preview the stage reconciliation scope with `node functions/reconcile.mjs PROJECT_ID`. Add `--apply` to recalculate existing students from current records. Archived profiles are preserved. Future requirement writes trigger recalculation independently of the student's browser.
4. Exercise a new account, a migrated account, a deployed student's resubmission and a coordinator-issued supervisor invitation on staging. An outstanding evaluation link must now pass mailbox verification. Each code is valid for ten minutes with five guesses, and verified submission access lasts one hour. The successful submission transaction consumes that access.

The local regression checks use fictional students and captured mail. With Firebase Auth and Firestore emulators on ports 9099 and 8080, run `node tools/student_enrollment_emulator_test.mjs`, `node tools/evaluation_invitation_emulator_test.mjs`, `node tools/evaluation_submission_emulator_test.mjs`, `node tools/evaluation_completion_emulator_test.mjs` and `node functions/stage_emulator_test.mjs`.
