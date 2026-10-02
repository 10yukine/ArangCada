-- The abandoned-registration sweep must not delete former administrators
-- (security audit, 1 Oct 2026).
--
-- Invited administrators are exempt from phone verification, so their
-- auth.users.phone_confirmed_at stays null, and they have no trips. Once
-- admin_remove_admin turned one back into a commuter, the account matched every
-- condition below and the next hourly run deleted it -- without the person
-- asking, and taking the actor off every admin_audit_logs row they wrote
-- (actor_id is ON DELETE SET NULL). admin_remove_admin's own contract is that
-- the person keeps an ordinary account they may delete themselves.
--
-- The admin audit log says who was an administrator: they wrote a row as actor,
-- or they are the target of 'admin_invite.accepted' (every invited admin) or
-- 'admin.removed' (every removed one), which covers admins who never took an
-- audited action. Being the target of any other action does not count -- an
-- unverified registration an admin suspended is still an abandoned
-- registration, and exempting it would let it hold its phone number for good.
-- It only narrows what the sweep deletes.
--
-- Regression: supabase/tests/89_audit_run2_followups_test.sql.
create or replace function public.sweep_abandoned_registrations(
  p_older_than interval default interval '2 hours'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  with doomed as (
    select u.id
      from auth.users u
      join public.profiles p on p.id = u.id
     where u.phone_confirmed_at is null
       and u.created_at < now() - p_older_than
       and coalesce(p.is_internal_tester, false) = false
       and p.role in ('commuter', 'driver')
       -- A driver record exists only because an administrator created it, which
       -- is enough to say the account is not an abandoned registration. Without
       -- this, a driver onboarded by an admin who never personally completed
       -- SMS verification matched every other condition -- and a newly approved
       -- driver has no trips yet by definition -- so the sweep would have
       -- deleted them, taking their verification documents with them.
       and not exists (
         select 1 from public.driver_profiles d where d.id = u.id
       )
       and not exists (
         select 1 from public.trips t
          where t.rider_id = u.id or t.driver_id = u.id
       )
       -- See the header: current and former administrators.
       and not exists (
         select 1 from public.admin_audit_logs l
          where l.actor_id = u.id
             or (l.target_profile_id = u.id
                 and l.action in ('admin_invite.accepted', 'admin.removed'))
       )
  )
  delete from auth.users u using doomed d where u.id = d.id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.sweep_abandoned_registrations(interval) is
  'Deletes accounts that never confirmed a mobile number and are older than the '
  'given age. Never touches internal testers, administrators, accounts with a '
  'driver record, accounts with trip history, or accounts the admin audit log '
  'shows were administrators. Two hours by default so a user who reopens the '
  'app can still finish verifying.';

revoke execute on function public.sweep_abandoned_registrations(interval)
  from public, anon, authenticated;
grant execute on function public.sweep_abandoned_registrations(interval) to service_role;
