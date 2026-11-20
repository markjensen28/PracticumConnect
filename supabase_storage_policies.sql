-- Run this in the Supabase SQL editor after enabling the Firebase Auth
-- third-party integration for the same Firebase project.
-- Deploy /api/document-download and its server-only SUPABASE_SERVICE_ROLE_KEY
-- alongside this migration. Student objects are append-only: resubmission uses
-- a new object path and preserves every previous version.

begin;

insert into storage.buckets (id, name, public)
values ('PracticumConnectStorage', 'PracticumConnectStorage', false)
on conflict (id) do update set public = false;

-- Firebase UIDs are strings, not PostgreSQL UUIDs, so compare the JWT subject
-- as text instead of calling auth.uid(). Every object path begins with the UID.

drop policy if exists "Firebase users upload to their own folder" on storage.objects;
drop policy if exists "Owners and staff read internship documents" on storage.objects;
drop policy if exists "Owners replace their internship documents" on storage.objects;
drop policy if exists "Owners and admins delete internship documents" on storage.objects;
drop policy if exists "Owners and staff delete internship documents" on storage.objects;

create policy "Firebase users upload to their own folder"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'PracticumConnectStorage'
  and (auth.jwt()->>'sub') is not null
  and ((auth.jwt()->>'app_role') in ('admin','coordinator') or
       ((auth.jwt()->>'app_role') = 'student' and auth.jwt()->>'student_enrolled' = 'true'
        and auth.jwt()->>'email_verified' = 'true'))
  and (storage.foldername(name))[1] = (auth.jwt()->>'sub')
  and (
    (storage.foldername(name))[2] is distinct from 'form_templates'
    or (auth.jwt()->>'app_role') in ('admin', 'coordinator')
  )
);

create policy "Owners and staff read internship documents"
on storage.objects for select
to anon, authenticated
using (
  bucket_id = 'PracticumConnectStorage'
  and (auth.jwt()->>'sub') is not null
  and ((auth.jwt()->>'app_role') in ('admin','coordinator') or
       ((auth.jwt()->>'app_role') = 'student' and auth.jwt()->>'student_enrolled' = 'true'
        and auth.jwt()->>'email_verified' = 'true'))
  and (
    (storage.foldername(name))[1] = (auth.jwt()->>'sub')
    or (auth.jwt()->>'app_role') = 'admin'
    -- Coordinators use /api/document-download, which checks the current
    -- Firestore assignment before signing. They cannot list student folders.
    -- Staff-published blank templates and completed samples are shared with
    -- signed-in users. Personal submissions stay in their existing folders.
    or (storage.foldername(name))[2] = 'form_templates'
  )
);

create policy "Owners replace their internship documents"
on storage.objects for update
to anon, authenticated
using (
  bucket_id = 'PracticumConnectStorage'
  and (auth.jwt()->>'app_role') in ('admin', 'coordinator')
  and (storage.foldername(name))[2] in ('form_templates', 'moas')
  and (storage.foldername(name))[1] = (auth.jwt()->>'sub')
  and (
    (storage.foldername(name))[2] is distinct from 'form_templates'
    or (auth.jwt()->>'app_role') in ('admin', 'coordinator')
  )
)
with check (
  bucket_id = 'PracticumConnectStorage'
  and (auth.jwt()->>'app_role') in ('admin', 'coordinator')
  and (storage.foldername(name))[2] in ('form_templates', 'moas')
  and (storage.foldername(name))[1] = (auth.jwt()->>'sub')
  and (
    (storage.foldername(name))[2] is distinct from 'form_templates'
    or (auth.jwt()->>'app_role') in ('admin', 'coordinator')
  )
);

create policy "Owners and admins delete internship documents"
on storage.objects for delete
to anon, authenticated
using (
  bucket_id = 'PracticumConnectStorage'
  and (
    ((auth.jwt()->>'app_role') = 'admin'
      and (storage.foldername(name))[2] in ('moas','form_templates'))
    or (
      (auth.jwt()->>'app_role') = 'coordinator'
      and (storage.foldername(name))[1] = (auth.jwt()->>'sub')
      and (storage.foldername(name))[2] = 'form_templates'
    )
  )
);

-- Evaluation objects are accessible only via scoped URLs issued by the API.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('practicum-evaluations','practicum-evaluations',false,10485760,array['application/pdf'])
on conflict (id) do update set public=false, file_size_limit=excluded.file_size_limit,
  allowed_mime_types=excluded.allowed_mime_types;

commit;
