-- pgTAP: Row Level Security, evaluated against real `authenticated` sessions.
--
-- WHY THIS FILE EXISTS
--
-- Six tables have RLS enabled and 17 policies between them, and until this file
-- landed not one policy had ever been evaluated. The runner connects as a
-- superuser, and PostgreSQL exempts superusers from row security completely. The
-- other suites therefore prove the schema and the fare arithmetic and say
-- nothing whatsoever about who can read what.
--
-- THE TRAP THIS FILE IS BUILT AROUND
--
-- The migrations contain no GRANT statements. Supabase pre-grants
-- anon/authenticated on the public schema and uses RLS as the only real gate; a
-- plain PostgreSQL instance grants nothing. So on an ungranted database:
--
--     set role authenticated;
--     select count(*) from public.profiles;   -->  ERROR: permission denied
--
-- not "0 rows". An assertion like "an authenticated user cannot see another
-- user's profile" would then PASS WHILE PROVING NOTHING -- it would pass just as
-- happily with RLS turned off, because the role never reaches the table at all.
--
-- 00_bootstrap_local.sql now issues the grants Supabase applies by default, so
-- what these assertions measure is policy evaluation and not a missing GRANT.
-- The negative control at the bottom of this file is what keeps that honest.
--
-- IMPERSONATION
--
--     set local role authenticated;
--     set local request.jwt.claim.sub = '<uuid>';
--
-- auth.uid() in the shim reads that claim. `set local` scopes it to this
-- transaction, which rolls back at the end.

begin;

select plan(35);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only -- no real names,
-- numbers, licence IDs, or coordinates (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'rider@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'driver@example.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'admin@example.test'),
  ('00000000-0000-0000-0000-0000000000d4', 'stranger@example.test');

insert into public.profiles (id, role, status, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', 'commuter', 'active', 'Test Rider'),
  ('00000000-0000-0000-0000-0000000000b2', 'driver',   'active', 'Test Driver'),
  ('00000000-0000-0000-0000-0000000000c3', 'admin',    'active', 'Test Admin'),
  ('00000000-0000-0000-0000-0000000000d4', 'commuter', 'active', 'Test Stranger');

insert into public.driver_documents (driver_id, document_type, storage_path)
values ('00000000-0000-0000-0000-0000000000b2', 'drivers_license', 'drivers/b2/license.jpg');

insert into public.trips (id, rider_id, driver_id, status, ride_type, pickup, dropoff)
values (
  '00000000-0000-0000-0000-00000000f001'::uuid,
  '00000000-0000-0000-0000-0000000000a1',
  '00000000-0000-0000-0000-0000000000b2',
  'requested',
  'special',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326)
);

-- ===========================================================================
-- RLS is actually switched on
-- ===========================================================================
select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.trips'::regclass),
  'trips has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.driver_documents'::regclass),
  'driver_documents has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.toda_zones'::regclass),
  'toda_zones has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.fare_matrix'::regclass),
  'fare_matrix has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.fare_discount_brackets'::regclass),
  'fare_discount_brackets has row security enabled'
);

-- ===========================================================================
-- profiles
-- ===========================================================================
savepoint before_rider;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from public.profiles),
  1,
  'a commuter sees exactly one profile row -- their own'
);

select is(
  (select id::text from public.profiles),
  '00000000-0000-0000-0000-0000000000a1',
  'and the row they see is their own, not somebody else''s'
);

select is(
  (select count(*)::int from public.profiles
    where id = '00000000-0000-0000-0000-0000000000d4'),
  0,
  'a commuter cannot read an unrelated commuter''s profile'
);

-- profiles has no INSERT policy at all. Self-service profile creation is
-- deliberately not a thing; creation belongs to a trigger or an admin path.
select throws_ok(
  $$insert into public.profiles (id, role, status, display_name)
    values ('00000000-0000-0000-0000-0000000000e5', 'admin', 'active', 'Self Made')$$,
  '42501',
  null,
  'a user cannot insert a profile row -- no INSERT policy exists, so no self-promotion to admin'
);

reset role;
rollback to savepoint before_rider;

-- ---------------------------------------------------------------------------
-- Admin reach
-- ---------------------------------------------------------------------------
savepoint before_admin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c3';

select is(
  (select count(*)::int from public.profiles),
  4,
  'an active admin reads every profile'
);

-- Two permissive SELECT policies both match an admin's own row
-- (profiles_select_own OR profiles_select_admin). Permissive policies are
-- OR-ed, they do not multiply rows -- but assert it rather than assume it.
select is(
  (select count(*)::int from public.profiles
    where id = '00000000-0000-0000-0000-0000000000c3'),
  1,
  'two overlapping permissive policies still yield one row, not a duplicate'
);

reset role;
rollback to savepoint before_admin;

-- ---------------------------------------------------------------------------
-- Anonymous
-- ---------------------------------------------------------------------------
savepoint before_anon;
set local role anon;

-- The profiles policies carry no TO clause, so they apply to PUBLIC, anon
-- included. This is safe only because auth.uid() is NULL for anon and
-- `id = NULL` evaluates to NULL rather than true. Safe by accident rather than
-- by design, which is exactly why it gets pinned here.
select is(
  (select count(*)::int from public.profiles),
  0,
  'anon reads no profiles -- auth.uid() is NULL and id = NULL is never true'
);

select is(
  (select count(*)::int from public.trips),
  0,
  'anon reads no trips'
);

select is(
  (select count(*)::int from public.driver_documents),
  0,
  'anon reads no driver documents'
);

reset role;
rollback to savepoint before_anon;

-- ===========================================================================
-- trips
-- ===========================================================================
savepoint before_trips;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from public.trips),
  1,
  'the rider on a trip can read it'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

select is(
  (select count(*)::int from public.trips),
  1,
  'the assigned driver can read the same trip'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d4';

select is(
  (select count(*)::int from public.trips),
  0,
  'an uninvolved user cannot read somebody else''s trip'
);

-- No UPDATE policy exists on trips for participants, and that is deliberate:
-- CLAUDE.md rule 7 puts status transitions behind trusted RPC. A driver writing
-- status straight from the handset is the exact thing that must stay impossible.
-- If someone later adds trips_update_participant, this assertion is the alarm.
select is(
  (select count(*)::int
     from pg_policies
    where schemaname = 'public'
      and tablename = 'trips'
      and cmd = 'UPDATE'
      and policyname <> 'trips_admin_all'),
  0,
  'trips has no participant UPDATE policy -- status must move through trusted RPC'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

-- Belt and braces: prove the absence of the policy actually blocks the write.
with attempted_update as (
  update public.trips set status = 'completed'
   where id = '00000000-0000-0000-0000-00000000f001'::uuid
  returning 1
)
select is(
  (select count(*)::int from attempted_update),
  0,
  'the assigned driver cannot mark their own trip completed directly'
);

-- A rider must not be able to book a trip in someone else's name.
select throws_ok(
  $$insert into public.trips (rider_id, status, ride_type, pickup, dropoff)
    values ('00000000-0000-0000-0000-0000000000d4', 'requested', 'special',
            st_setsrid(st_makepoint(121.165, 14.215), 4326),
            st_setsrid(st_makepoint(121.170, 14.220), 4326))$$,
  '42501',
  null,
  'a user cannot create a trip on another commuter''s behalf'
);

reset role;
rollback to savepoint before_trips;

-- ===========================================================================
-- driver_documents -- the most sensitive table in the schema
-- ===========================================================================
savepoint before_docs;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

select is(
  (select count(*)::int from public.driver_documents),
  1,
  'a driver reads their own submitted document'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d4';

select is(
  (select count(*)::int from public.driver_documents),
  0,
  'another user cannot read that driver''s document'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c3';

select is(
  (select count(*)::int from public.driver_documents),
  1,
  'an admin can read driver documents for verification'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

-- Only SELECT and INSERT policies exist for the owner. No UPDATE, no DELETE:
-- a submitted document cannot be quietly swapped or withdrawn after review.
with attempted_delete as (
  delete from public.driver_documents
   where driver_id = '00000000-0000-0000-0000-0000000000b2'
  returning 1
)
select is(
  (select count(*)::int from attempted_delete),
  0,
  'a driver cannot delete a submitted document -- the audit trail holds'
);

select throws_ok(
  $$insert into public.driver_documents (driver_id, document_type, storage_path)
    values ('00000000-0000-0000-0000-0000000000d4', 'drivers_license', 'drivers/d4/forged.jpg')$$,
  '42501',
  null,
  'a driver cannot file a document against another driver''s account'
);

reset role;
rollback to savepoint before_docs;

-- ===========================================================================
-- Reference data: only active rows are visible
-- ===========================================================================
savepoint before_ref;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from public.toda_zones where not is_active),
  0,
  'a deactivated TODA zone is invisible to clients'
);

select is(
  (select count(*)::int from public.fare_matrix where not is_active),
  0,
  'a superseded fare row is invisible to clients -- no stale fare can be quoted'
);

-- NOTE THE ASYMMETRY, it matters for the Flutter client later.
--
-- A blocked INSERT raises 42501, because WITH CHECK is evaluated against the
-- row being written and fails loudly. A blocked UPDATE does not raise anything:
-- the USING clause of fare_matrix_admin_write simply makes zero rows visible to
-- update, so the statement succeeds and reports 0 rows affected.
--
-- The data is equally safe either way, but the client sees a silent no-op
-- rather than an error. Any repository method that updates a protected table
-- must check the affected-row count instead of relying on an exception.
with attempted_fare_edit as (
  update public.fare_matrix set base_fare_centavos = 1
  returning 1
)
select is(
  (select count(*)::int from attempted_fare_edit),
  0,
  'a commuter cannot rewrite the LGU fare matrix -- zero rows updated, silently'
);

select throws_ok(
  $$insert into public.toda_zones (code, name, boundary, is_active)
    values ('CAL-FAKE-99', 'Invented TODA',
            st_geomfromtext('POLYGON((121.1 14.1,121.2 14.1,121.2 14.2,121.1 14.2,121.1 14.1))', 4326),
            true)$$,
  '42501',
  null,
  'a commuter cannot invent a TODA jurisdiction'
);

reset role;
rollback to savepoint before_ref;

-- ===========================================================================
-- is_admin()
-- ===========================================================================
select ok(
  not public.is_admin('00000000-0000-0000-0000-0000000000a1'),
  'is_admin() is false for a commuter'
);

select ok(
  public.is_admin('00000000-0000-0000-0000-0000000000c3'),
  'is_admin() is true for an active admin'
);

update public.profiles set status = 'suspended'
 where id = '00000000-0000-0000-0000-0000000000c3';

select ok(
  not public.is_admin('00000000-0000-0000-0000-0000000000c3'),
  'a suspended admin loses admin rights -- is_admin() requires status = active'
);

update public.profiles set status = 'active'
 where id = '00000000-0000-0000-0000-0000000000c3';

select ok(
  not public.is_admin('00000000-0000-0000-0000-00000000ffff'),
  'is_admin() on an unknown uuid returns false rather than erroring'
);

-- ===========================================================================
-- NEGATIVE CONTROL
--
-- Everything above is only meaningful if the zero-row results come from policy
-- evaluation rather than from a missing GRANT. This proves the difference: the
-- same query that returns 0 rows as `authenticated` must return rows for a role
-- that bypasses RLS. If grants were the real gatekeeper, this would error or
-- return 0 and the suite would fail loudly.
-- ===========================================================================
savepoint before_control;
set local role service_role;   -- created BYPASSRLS in the shim

select cmp_ok(
  (select count(*)::int from public.profiles),
  '>',
  0,
  'NEGATIVE CONTROL: a BYPASSRLS role still sees profiles, so the zero-row results above came from RLS and not from a missing GRANT'
);

reset role;

-- No `rollback to savepoint` here on purpose. pgTAP records results in a
-- transactional store, so rolling back after the final assertion discards it and
-- finish() then reports one fewer test than actually ran. The outer `rollback`
-- below cleans up everything this file touched anyway.

select * from finish();

rollback;
