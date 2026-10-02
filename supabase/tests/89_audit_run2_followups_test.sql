-- Security audit follow-ups, 1 Oct 2026:
-- 20261001090000 (definer RPCs without PUBLIC execute) and
-- 20261001091000 (the sweep spares former administrators).
begin;
select plan(16);

-- 20261001090000 -------------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.admin_finalize_invited_account(text, uuid, text, text)', 'execute'),
  'anon cannot execute admin_finalize_invited_account');
select ok(not has_function_privilege('authenticated', 'public.driver_finalize_invited_account(text, uuid)', 'execute'),
  'a signed-in user cannot execute driver_finalize_invited_account');
select ok(not has_function_privilege('anon', 'public.admin_list_drivers()', 'execute'),
  'anon cannot execute admin_list_drivers');
select ok(not has_function_privilege('anon', 'public.admin_update_driver_name(uuid, text, text, text)', 'execute'),
  'anon cannot execute admin_update_driver_name');
select ok(not has_function_privilege('anon', 'public.admin_update_driver_record(uuid, text, text, text, text, uuid, date)', 'execute'),
  'anon cannot execute admin_update_driver_record');

select ok(has_function_privilege('service_role', 'public.admin_finalize_invited_account(text, uuid, text, text)', 'execute')
      and has_function_privilege('service_role', 'public.driver_finalize_invited_account(text, uuid)', 'execute'),
  'the accept-invite functions can still finalize as service_role');
select ok(has_function_privilege('authenticated', 'public.admin_list_drivers()', 'execute')
      and has_function_privilege('authenticated', 'public.admin_update_driver_name(uuid, text, text, text)', 'execute')
      and has_function_privilege('authenticated', 'public.admin_update_driver_record(uuid, text, text, text, text, uuid, date)', 'execute'),
  'the admin console can still call its three driver RPCs');

-- A later migration that creates a definer function and forgets PUBLIC fails here.
select is_empty($$
  select p.oid::regprocedure::text
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.prosecdef
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
     and exists (
       select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
        where a.grantee = 0 and a.privilege_type = 'EXECUTE')
$$, 'no SECURITY DEFINER function in public grants EXECUTE to PUBLIC');

-- 20261001091000 -------------------------------------------------------------

insert into auth.users(id, email, raw_user_meta_data, created_at) values
('00000000-0000-0000-0000-000000008901', 'r2-lgu@example.test', '{"display_name":"R2 Lgu","mobile_number":"+639170008901"}', now() - interval '3 days'),
('00000000-0000-0000-0000-000000008902', 'r2-former@example.test', '{"display_name":"R2 Former","invited_admin":"true"}', now() - interval '3 days'),
('00000000-0000-0000-0000-000000008903', 'r2-silent@example.test', '{"display_name":"R2 Silent","invited_admin":"true"}', now() - interval '3 days'),
('00000000-0000-0000-0000-000000008904', 'r2-abandoned@example.test', '{"display_name":"R2 Abandoned","mobile_number":"+639170008904"}', now() - interval '3 days'),
('00000000-0000-0000-0000-000000008905', 'r2-suspended@example.test', '{"display_name":"R2 Suspended","mobile_number":"+639170008905"}', now() - interval '3 days');
update public.profiles set role = 'admin' where id in
  ('00000000-0000-0000-0000-000000008901', '00000000-0000-0000-0000-000000008902', '00000000-0000-0000-0000-000000008903');
-- ...8902 took an audited action while an admin; ...8903 never did.
insert into public.admin_audit_logs(actor_id, action, target_profile_id)
values ('00000000-0000-0000-0000-000000008902', 'driver.approve', '00000000-0000-0000-0000-000000008901');
-- ...8905 never verified a phone and an admin suspended it. That is still an
-- abandoned registration: only having been an administrator exempts an account.
insert into public.admin_audit_logs(actor_id, action, target_profile_id)
values ('00000000-0000-0000-0000-000000008901', 'profile.suspend', '00000000-0000-0000-0000-000000008905');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008901';
select lives_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008902')$$,
  'an LGU admin removes an invited admin who never verified a phone');
select lives_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008903')$$,
  'and one who never took an audited action');

reset role;
select is(public.sweep_abandoned_registrations(), 2,
  'the sweep deletes only the two abandoned registrations');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-000000008904'),
  0, 'the abandoned registration is gone');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-000000008905'),
  0, 'and so is the one an admin had suspended');
select is((select count(*)::int from auth.users where id in
  ('00000000-0000-0000-0000-000000008902', '00000000-0000-0000-0000-000000008903')),
  2, 'both former administrators keep their accounts');
select is((select role::text from public.profiles where id = '00000000-0000-0000-0000-000000008902'),
  'commuter', 'as ordinary commuter accounts');
select is((select actor_id from public.admin_audit_logs where action = 'driver.approve'
            and target_profile_id = '00000000-0000-0000-0000-000000008901'),
  '00000000-0000-0000-0000-000000008902'::uuid, 'and the audit log still names who acted');

select * from finish();
rollback;
