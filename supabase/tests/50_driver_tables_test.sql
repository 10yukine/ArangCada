-- pgTAP: driver_profiles, toda_members, and admin_audit_logs -- schema and RLS.
--
-- WHY THIS FILE EXISTS
--
-- These three tables carry the authorization state for driver onboarding, and
-- the interesting assertions are all about what is DENIED. Two of them are
-- deliberately missing policies that a reader might assume are simply
-- forgotten:
--
--   * driver_profiles has SELECT for admins but no admin write policy, so an
--     approval cannot happen without the audit row an RPC writes;
--   * admin_audit_logs has no insert policy for anyone at all, so no session
--     can forge or suppress an entry.
--
-- A missing policy looks identical to an oversight in the migration file. These
-- assertions are what make the absence deliberate and keep a future
-- "convenience" policy from being added without a test turning red.
--
-- The RPCs that legitimately write these tables do not exist yet; this file
-- covers the schema layer they will run against.

begin;

select plan(25);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000050a1', 'dt-commuter@example.test',
     '{"display_name":"DT Commuter","mobile_number":"+639170000501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000050b2', 'dt-driver@example.test',
     '{"display_name":"DT Driver","mobile_number":"+639170000502"}'::jsonb),
  ('00000000-0000-0000-0000-0000000050b3', 'dt-driver2@example.test',
     '{"display_name":"DT Driver Two","mobile_number":"+639170000503"}'::jsonb),
  ('00000000-0000-0000-0000-0000000050c3', 'dt-admin@example.test',
     '{"display_name":"DT Admin","mobile_number":"+639170000504"}'::jsonb);

update public.profiles set role = 'driver'
 where id in ('00000000-0000-0000-0000-0000000050b2',
              '00000000-0000-0000-0000-0000000050b3');
update public.profiles set role = 'admin'
 where id = '00000000-0000-0000-0000-0000000050c3';

-- Borrow a seeded TODA zone rather than inventing geometry.
create temporary table dt_zone as
  select id from public.toda_zones order by code limit 1;

insert into public.toda_members (toda_zone_id, member_name, body_number, plate_number)
select id, 'DT Roster Member', 'DT-001', 'ABC 1234' from dt_zone;

insert into public.driver_profiles (id, toda_zone_id, body_number, promoted_by)
select '00000000-0000-0000-0000-0000000050b2', id, 'DT-101',
       '00000000-0000-0000-0000-0000000050c3'
  from dt_zone;

-- ===========================================================================
-- RLS is actually switched on
-- ===========================================================================
select ok(
  (select relrowsecurity from pg_class where oid = 'public.driver_profiles'::regclass),
  'driver_profiles has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.toda_members'::regclass),
  'toda_members has row security enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.admin_audit_logs'::regclass),
  'admin_audit_logs has row security enabled'
);

-- ===========================================================================
-- Constraints that encode design decisions
-- ===========================================================================

-- Partial unique index: several drivers may sit at a null body number while
-- the TODA assigns them, but two drivers cannot share a real one.
select lives_ok(
  $$insert into public.driver_profiles (id, toda_zone_id, body_number, promoted_by)
    select '00000000-0000-0000-0000-0000000050b3', id, null,
           '00000000-0000-0000-0000-0000000050c3' from dt_zone$$,
  'a second driver in the same zone may also have a null body number'
);

select throws_ok(
  $$update public.driver_profiles set body_number = 'DT-101'
     where id = '00000000-0000-0000-0000-0000000050b3'$$,
  '23505',
  null,
  'but two drivers in one zone cannot share the same non-null body number'
);

select throws_ok(
  $$update public.driver_profiles set verification_status = 'rejected'
     where id = '00000000-0000-0000-0000-0000000050b2'$$,
  '23514',
  null,
  'a driver cannot be rejected without a rejection_reason'
);

select lives_ok(
  $$update public.driver_profiles
       set verification_status = 'rejected', rejection_reason = 'Test reason'
     where id = '00000000-0000-0000-0000-0000000050b2'$$,
  'rejecting with a reason is accepted'
);

-- Suspension lives on profiles.status, so it must NOT be a verification state.
select throws_ok(
  $$select 'suspended'::public.driver_verification_status$$,
  null, null,
  'driver_verification_status has no "suspended" value -- suspension lives on profiles.status, one fact one source'
);

-- ---------------------------------------------------------------------------
-- admin_audit_logs rejects identity-bearing metadata keys
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.admin_audit_logs (actor_id, action, metadata)
    values ('00000000-0000-0000-0000-0000000050c3', 'driver.promote',
            '{"phone":"+639170000502"}'::jsonb)$$,
  '23514',
  null,
  'admin_audit_logs refuses metadata carrying a phone number (CLAUDE.md rule 10)'
);

select throws_ok(
  $$insert into public.admin_audit_logs (actor_id, action, metadata)
    values ('00000000-0000-0000-0000-0000000050c3', 'driver.promote',
            '{"display_name":"DT Driver"}'::jsonb)$$,
  '23514',
  null,
  'and refuses metadata carrying a display name'
);

select lives_ok(
  $$insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
    values ('00000000-0000-0000-0000-0000000050c3', 'driver.promote',
            '00000000-0000-0000-0000-0000000050b2',
            '{"toda_zone_code":"TEST"}'::jsonb)$$,
  'while non-identity metadata is accepted -- reference people by uuid instead'
);

-- ===========================================================================
-- toda_members: a roster of real names and plates, admin-readable only
-- ===========================================================================
savepoint before_commuter;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000050a1';

select is(
  (select count(*)::int from public.toda_members),
  0,
  'a commuter cannot read the TODA roster'
);

select is(
  (select count(*)::int from public.driver_profiles),
  0,
  'a commuter cannot read any driver record'
);

reset role;
rollback to savepoint before_commuter;

savepoint before_driver;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000050b2';

select is(
  (select count(*)::int from public.toda_members),
  0,
  'a driver cannot read the roster either -- not even the entry describing them'
);

select is(
  (select count(*)::int from public.driver_profiles),
  1,
  'a driver reads exactly one driver record'
);

select is(
  (select id::text from public.driver_profiles),
  '00000000-0000-0000-0000-0000000050b2',
  'and it is their own, not another driver''s'
);

select is(
  (select count(*)::int from public.admin_audit_logs),
  0,
  'a driver cannot read the admin audit log'
);

reset role;
rollback to savepoint before_driver;

-- ===========================================================================
-- Admin reach, and its deliberate limits
-- ===========================================================================
savepoint before_admin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000050c3';

select is(
  (select count(*)::int from public.toda_members),
  1,
  'an admin reads the TODA roster'
);

select is(
  (select count(*)::int from public.driver_profiles),
  2,
  'an admin reads every driver record'
);

select cmp_ok(
  (select count(*)::int from public.admin_audit_logs),
  '>', 0,
  'an admin reads the audit log'
);

-- The absences. Each of these would be an audit-integrity hole, not an RLS
-- hole -- is_admin() is a real check either way. They are refused so that
-- state changes cannot happen without the RPC that records them.
-- NOTE THE FAILURE MODE. RLS selects the rows an UPDATE may touch through a
-- policy's USING clause; with no UPDATE policy at all, nothing qualifies, so
-- the statement SUCCEEDS and reports zero rows affected rather than raising.
-- That is quieter than an error and worth stating plainly: admin_web code
-- issuing a direct PATCH here would look like it worked while changing
-- nothing. The security property still holds -- the state does not move -- but
-- any repository method that writes a protected table must check its rowcount
-- rather than trusting the absence of an exception. The same trap is
-- documented in 40_rls_test.sql for fare_matrix.
with attempted_approval as (
  update public.driver_profiles set verification_status = 'approved'
   where id = '00000000-0000-0000-0000-0000000050b2'
  returning 1
)
select is(
  (select count(*)::int from attempted_approval),
  0,
  'an admin cannot approve a driver by direct update -- zero rows affected, silently, so it must go through an audited RPC'
);

select throws_ok(
  $$insert into public.admin_audit_logs (actor_id, action)
    values ('00000000-0000-0000-0000-0000000050c3', 'forged.entry')$$,
  null, null,
  'an admin cannot forge an audit entry -- there is no insert policy for anyone'
);

with attempted_erasure as (
  delete from public.admin_audit_logs returning 1
)
select is(
  (select count(*)::int from attempted_erasure),
  0,
  'an admin cannot erase audit entries either -- zero rows deleted, no delete policy exists'
);

select throws_ok(
  $$insert into public.toda_members (toda_zone_id, member_name, body_number)
    select id, 'Injected Member', 'DT-999' from dt_zone$$,
  null, null,
  'an admin cannot edit the roster from a session -- it is version-controlled reference data'
);

reset role;
rollback to savepoint before_admin;

-- ===========================================================================
-- NEGATIVE CONTROL
-- ===========================================================================
savepoint before_control;
set local role service_role;

select cmp_ok(
  (select count(*)::int from public.driver_profiles),
  '>', 0,
  'NEGATIVE CONTROL: a BYPASSRLS role still sees driver_profiles, so the zero-row results above came from RLS and not from a missing GRANT'
);

reset role;

select * from finish();

rollback;
