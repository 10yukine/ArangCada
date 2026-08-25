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
-- needs (display_name, phone).
--
-- See .pipeline/specs.md, "Commuter-first driver onboarding, server layer",
-- §1 problem statement and §4 20260825120100_profiles_privileged_column_guard.

begin;

select plan(8);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000010a1', 'privtest-commuter@example.test'),
  ('00000000-0000-0000-0000-0000000010c3', 'privtest-admin@example.test');

insert into public.profiles (id, role, status, display_name, phone) values
  ('00000000-0000-0000-0000-0000000010a1', 'commuter', 'active', 'Priv Test Commuter', '+639170000101'),
  ('00000000-0000-0000-0000-0000000010c3', 'admin',    'active', 'Priv Test Admin',    '+639170000103');

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

select lives_ok(
  $$update public.profiles set phone = '+639170000199'
     where id = '00000000-0000-0000-0000-0000000010a1'$$,
  'a commuter can still update their own phone'
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
