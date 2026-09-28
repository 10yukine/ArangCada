-- pgTAP: profiles column-level privilege boundary.
--
-- WHY THIS FILE EXISTS
--
-- profiles_update_own (20260728090100_profiles.sql) restricts UPDATE by ROW
-- (id = auth.uid()) but not by COLUMN, and no compensating GRANT narrows
-- which columns `authenticated` may write. The consequence, provable today
-- against an unpatched database:
--
--     set role authenticated;
--     update profiles set role = 'admin' where id = auth.uid();
--
-- succeeds. Any signed-in commuter can make themselves an admin. This file
-- exists to make that failure visible in the test suite rather than only in
-- prose, and to prove the fix (column grants + a guard trigger) closes it
-- without also blocking the self-service updates a commuter legitimately
-- needs (display_name; phone now changes only via OTP).
--
-- See .pipeline/specs.md, "Commuter-first driver onboarding, server layer",
-- §1 problem statement and §4 20260825120100_profiles_privileged_column_guard.

begin;

select plan(10);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
-- handle_new_user() (20260825120050) builds the profiles rows from this
-- metadata; inserting them directly would collide on the primary key.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000010a1', 'privtest-commuter@example.test',
     '{"display_name":"Priv Test Commuter","mobile_number":"+639170000101"}'::jsonb),
  ('00000000-0000-0000-0000-0000000010c3', 'privtest-admin@example.test',
     '{"display_name":"Priv Test Admin","mobile_number":"+639170000103"}'::jsonb);

update public.profiles set role = 'admin'
 where id = '00000000-0000-0000-0000-0000000010c3';

-- ===========================================================================
-- A commuter cannot escalate their own role or status
-- ===========================================================================
savepoint before_commuter;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000010a1';

select throws_ok(
  $$update public.profiles set role = 'admin'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  null, null,
  'a commuter cannot set their own role to admin'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000010a1'),
  'commuter',
  'role is unchanged after the rejected attempt'
);

select throws_ok(
  $$update public.profiles set status = 'suspended'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  null, null,
  'a commuter cannot set their own status to suspended'
);

-- ---------------------------------------------------------------------------
-- The fix must not be a blanket lockout -- these two columns stay writable.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$update public.profiles set display_name = 'Updated Name'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  'a commuter can still update their own display_name'
);

-- Phone changes only through the OTP phone-change flow; the auth.users
-- trigger mirrors the confirmed number (20260928141000).
select throws_ok(
  $$update public.profiles set phone = '+639170000199'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  '42501', null,
  'a commuter cannot change their phone without OTP'
);

-- email resolves accounts during driver onboarding, so it is authorization-
-- adjacent in the same way role is. It changes only through Supabase Auth's
-- own email-change flow (mirrored by sync_profile_email), never a direct
-- patch -- otherwise a user could point their profile at somebody else'''s
-- address and be found by an admin looking that address up.
select throws_ok(
  $$update public.profiles set email = 'someone-else@example.test'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  null, null,
  'a commuter cannot change their own email by patching profiles directly'
);

reset role;
rollback to savepoint before_commuter;

-- ===========================================================================
-- Not even an admin's own authenticated session gets a direct write. A raw
-- PATCH would write no admin_audit_logs row, silently defeating "every
-- promote, demote, approve, reject, suspend, and unsuspend writes exactly
-- one audit row" -- every change goes through a security definer RPC
-- instead, which this file cannot exercise yet (they do not exist until a
-- later migration); this assertion only proves the direct path stays shut.
-- ===========================================================================
savepoint before_admin;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000010c3';

select throws_ok(
  $$update public.profiles set status = 'suspended'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  null, null,
  'even an admin''s own authenticated session cannot directly patch another profile''s status -- must go through an audited RPC'
);

reset role;
rollback to savepoint before_admin;

-- ===========================================================================
-- service_role bypasses the trigger entirely (used by the onboarding RPCs,
-- which run security definer as the function owner, not as `authenticated`)
-- ===========================================================================
savepoint before_service;
set local role service_role;

select lives_ok(
  $$update public.profiles set role = 'driver'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  'service_role can change role -- the trusted path the security definer RPCs use'
);

reset role;
rollback to savepoint before_service;

-- ===========================================================================
-- LAYER 2 IN ISOLATION
--
-- Everything above passes on the column GRANT alone -- `authenticated` is
-- refused at the table before the trigger ever runs, so those assertions
-- prove the behaviour but say nothing about whether the trigger works. The
-- trigger exists specifically for the case where a later migration re-grants
-- the table wholesale (the same class of drift
-- 20260816160000_revoke_public_rls_auto_enable.sql was written to close).
-- Simulate exactly that here: hand the privilege back, then confirm the
-- escalation is still refused, this time by the trigger.
-- ===========================================================================
savepoint before_regrant;
grant update on public.profiles to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000010a1';

select throws_ok(
  $$update public.profiles set role = 'admin'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  '42501',
  'profiles.role and profiles.status can only change through a security definer RPC, never a direct update',
  'with the table grant carelessly restored, the trigger alone still blocks escalation'
);

reset role;
rollback to savepoint before_regrant;

-- ===========================================================================
-- NEGATIVE CONTROL: prove the guard is column privilege / trigger logic, not
-- an accidental RLS side effect that would also block the writes above.
-- ===========================================================================
select is(
  (select count(*)::int from public.profiles
    where id in (
      '00000000-0000-0000-0000-0000000010a1',
      '00000000-0000-0000-0000-0000000010c3'
    )),
  2,
  'NEGATIVE CONTROL: both fixture rows are still present and readable -- prior failures were the write guard, not a row disappearing'
);

select * from finish();

rollback;
