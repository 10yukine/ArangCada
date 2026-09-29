-- Close a live privilege-escalation defect.
--
-- profiles_update_own (20260728090100_profiles.sql) restricts UPDATE by row
-- (id = auth.uid()) but not by column, and no compensating GRANT narrows
-- which columns `authenticated` may write. The consequence, provable today:
--
--     set role authenticated;
--     update profiles set role = 'admin' where id = auth.uid();
--
-- succeeds. Any signed-in commuter can make themselves an admin.
-- supabase/tests/45_profiles_privilege_test.sql proves this fails without
-- this migration.
--
-- Two layers, deliberately redundant:
--
--   1. Column grants are the primary control. Supabase pre-grants
--      `authenticated` a blanket UPDATE on every public table (see
--      supabase/tests/00_bootstrap_local.sql, which reproduces that default
--      for local testing). REVOKE it, then GRANT back only the two columns a
--      user should ever change about themselves.
--   2. A BEFORE UPDATE trigger is a second layer that keeps working even if
--      a future migration accidentally re-grants the table wholesale --
--      exactly the kind of drift 20260816160000_revoke_public_rls_auto_enable.sql
--      exists to close for a different function.
--
-- The trigger is DEFAULT-ALLOW, deny only `authenticated`, not the reverse.
-- A BEFORE UPDATE trigger fires on every UPDATE regardless of RLS bypass
-- status -- superuser and BYPASSRLS do not exempt a row from a trigger the
-- way they exempt it from a policy. PostgREST is the only caller that ever
-- connects as literally `authenticated`; migrations, seed data, the Supabase
-- SQL editor, and this repo's own test runner all run as a superuser-equivalent
-- role and must keep working untouched. A default-deny version of this
-- trigger was tried first and broke exactly that: it blocked
-- supabase/tests/40_rls_test.sql's own is_admin() fixture updates, which run
-- with no impersonation active at all.
--
-- No admin carve-out. An earlier version of this trigger let an admin's own
-- `authenticated` session patch role/status directly, on the theory that an
-- admin should be able to. supabase/tests/45_profiles_privilege_test.sql
-- caught why that is wrong: a raw PATCH writes no
-- `admin_audit_logs` row, silently defeating the "every promote, demote,
-- approve, reject, suspend, and unsuspend writes exactly one audit row"
-- success criterion. Every role/status change --
-- admin included -- must go through a `security definer` RPC
-- (`admin_promote_commuter_to_driver`, `admin_demote_driver`,
-- `admin_set_profile_status`, ...). Those functions execute as their owner,
-- not literally as `authenticated`, so this trigger does not need to
-- recognise them specially -- it simply never sees `current_user =
-- 'authenticated'` from inside one.

revoke update on public.profiles from authenticated;
grant update (display_name, phone) on public.profiles to authenticated;

create or replace function public.guard_profiles_privileged_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user = 'authenticated'
     and (new.role is distinct from old.role
          or new.status is distinct from old.status) then
    raise exception 'profiles.role and profiles.status can only change through a security definer RPC, never a direct update'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

comment on function public.guard_profiles_privileged_columns() is
  'Blocks every authenticated session, admin included, from changing '
  'role/status directly. Default-allow for every other execution context '
  '(migrations, seed data, and the security definer RPCs, which run as their '
  'owner), "Commuter-first driver onboarding, '
  'server layer", §1.';

create trigger profiles_guard_privileged_columns
  before update on public.profiles
  for each row
  execute function public.guard_profiles_privileged_columns();
