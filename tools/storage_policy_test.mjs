// Run with @electric-sql/pglite installed. Uses an ephemeral local PostgreSQL
// engine and minimal Supabase-compatible schemas; never connects to production.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const db = new PGlite();
try {
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema storage;
    create schema auth;
    create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
    create table storage.objects (bucket_id text, name text, payload text, primary key(bucket_id, name));
    create function auth.jwt() returns jsonb language sql stable as $$
      select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
    $$;
    create function storage.foldername(name text) returns text[] language sql immutable as $$
      select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1)-1]
    $$;
    alter table storage.objects enable row level security;
    grant usage on schema storage, auth to anon, authenticated;
    grant select, insert, update, delete on storage.objects to anon, authenticated;
    insert into storage.objects values
      ('PracticumConnectStorage', 'student/requirements/approved.pdf', 'original'),
      ('PracticumConnectStorage', 'other/requirements/private.pdf', 'private'),
      ('practicum-evaluations','invitation/completed.pdf','confidential'),
      ('PracticumConnectStorage', 'staff/form_templates/blank.pdf', 'template');
  `);
  const policies = readFileSync('supabase_storage_policies.sql', 'utf8');
  await db.exec(policies);
  await db.exec(policies); // Migration must remain safe to rerun.
  async function as(uid, role) {
    await db.exec('reset role');
    await db.query("select set_config('request.jwt.claims', $1, false)", [JSON.stringify({ sub: uid, app_role: role, student_enrolled: role === 'student', email_verified: true })]);
    await db.exec('set role authenticated');
  }
  await as('staff', 'coordinator');
  const staffFiles = await db.query('select name from storage.objects order by name');
  assert.deepEqual(staffFiles.rows.map(row => row.name), ['staff/form_templates/blank.pdf']);
  console.log('PASS: coordinator cannot list or read student objects directly');
  await as('student', undefined);
  assert.equal((await db.query('select name from storage.objects')).rows.length, 0);
  await assert.rejects(db.exec("insert into storage.objects values ('PracticumConnectStorage','student/requirements/inactive.pdf','test')"));
  await as('student', 'student');
  assert.equal((await db.query("select * from storage.objects where name = 'student/requirements/approved.pdf'")).rows.length, 1);
  assert.equal((await db.query("update storage.objects set payload = 'tampered' where name = 'student/requirements/approved.pdf' returning name")).rows.length, 0);
  assert.equal((await db.query("delete from storage.objects where name = 'student/requirements/approved.pdf' returning name")).rows.length, 0);
  await assert.rejects(db.exec("insert into storage.objects values ('PracticumConnectStorage', 'student/requirements/approved.pdf', 'tampered') on conflict (bucket_id, name) do update set payload = excluded.payload"));
  assert.equal((await db.query("select payload from storage.objects where name = 'student/requirements/approved.pdf'")).rows[0].payload, 'original');
  console.log('PASS: student cannot overwrite, upsert over, or delete an existing object');
  await db.exec("insert into storage.objects values ('PracticumConnectStorage', 'student/requirements/new-version.pdf', 'correction')");
  await assert.rejects(db.exec("insert into storage.objects values ('PracticumConnectStorage', 'other/requirements/forged.pdf', 'forged')"));
  await assert.rejects(db.exec("insert into storage.objects values ('PracticumConnectStorage', 'student/form_templates/leak.pdf', 'forged')"));
  console.log('PASS: new owned versions allowed; foreign uploads and student templates denied');
  await db.exec("insert into storage.objects values ('PracticumConnectStorage','student/dtr-checkins/photo.jpg','original photo')");
  await as('admin', 'admin');
  assert.equal((await db.query('select * from storage.objects')).rows.length, 5);
  assert.equal((await db.query("update storage.objects set payload='replacement' where name='student/dtr-checkins/photo.jpg' returning name")).rows.length,0);
  assert.equal((await db.query("delete from storage.objects where name='student/dtr-checkins/photo.jpg' returning name")).rows.length,0);
  assert.equal((await db.query("delete from storage.objects where name = 'student/requirements/approved.pdf' returning name")).rows.length, 0);
  assert.equal((await db.query("delete from storage.objects where name = 'staff/form_templates/blank.pdf' returning name")).rows.length, 1);
  console.log('PASS: admin can maintain blank templates while submitted files are retained');
} finally { await db.close(); }
