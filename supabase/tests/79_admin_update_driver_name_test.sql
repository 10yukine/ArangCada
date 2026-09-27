-- pgTAP: admin_update_driver_name and widened admin_list_drivers

begin;

select plan(14);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000079c1', 'ud-lgu@example.test',
     '{"display_name":"Ud Lgu","mobile_number":"+639170007901"}'::jsonb),
  ('00000000-0000-0000-0000-0000000079c2', 'ud-toda@example.test',
     '{"display_name":"Ud Toda","mobile_number":"+639170007902"}'::jsonb),
  ('00000000-0000-0000-0000-0000000079a1', 'ud-commuter@example.test',
     '{"display_name":"Ud Commuter","mobile_number":"+639170007903"}'::jsonb),
  ('00000000-0000-0000-0000-0000000079d1', 'ud-driver1@example.test',
     '{"display_name":"Driver One","mobile_number":"+639170007904"}'::jsonb),
  ('00000000-0000-0000-0000-0000000079d2', 'ud-driver2@example.test',
     '{"display_name":"Driver Two","mobile_number":"+639170007905"}'::jsonb);

update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000079__';

update public.profiles set role = 'admin' where id in (
  '00000000-0000-0000-0000-0000000079c1', '00000000-0000-0000-0000-0000000079c2'
);

create temporary table ud_zone_a as
  select id, name from public.toda_zones where is_active order by code limit 1;
grant select on ud_zone_a to authenticated, service_role, anon;

create temporary table ud_zone_b as
  select id, name from public.toda_zones where is_active order by code offset 1 limit 1;
grant select on ud_zone_b to authenticated, service_role, anon;

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
values ('00000000-0000-0000-0000-0000000079c2', 'toda', (select id from ud_zone_a));

-- Promote drivers
update public.profiles set role = 'driver' where id in (
  '00000000-0000-0000-0000-0000000079d1', '00000000-0000-0000-0000-0000000079d2'
);

insert into public.driver_profiles (
  id, toda_zone_id, body_number, plate_number, verification_status, promoted_by
) values
  ('00000000-0000-0000-0000-0000000079d1', (select id from ud_zone_a), '101', '101-AAA', 'approved', '00000000-0000-0000-0000-0000000079c1'),
  ('00000000-0000-0000-0000-0000000079d2', (select id from ud_zone_b), '202', '202-BBB', 'approved', '00000000-0000-0000-0000-0000000079c1');

-- ===========================================================================
-- Authorization and Validation Tests
-- ===========================================================================

-- 1. Commuter cannot call admin_update_driver_name
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079a1';

select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d1', 'New', 'Name')$$,
  '42501', null,
  'a commuter cannot update a driver name'
);

-- 2. Driver cannot call admin_update_driver_name
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079d1';

select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d1', 'New', 'Name')$$,
  '42501', null,
  'a driver cannot update their own name via admin_update_driver_name'
);

-- 3. TODA admin cannot update driver outside their TODA
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c2';

select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d2', 'New', 'Name')$$,
  '42501', null,
  'a TODA admin cannot update a driver in another TODA'
);

-- 4. Empty first name rejected
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c1';

select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d1', '  ', 'Name')$$,
  '22023', null,
  'empty first name is rejected'
);

-- 5. Empty last name rejected
select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d1', 'First', '  ')$$,
  '22023', null,
  'empty last name is rejected'
);

-- 6. Non-existent driver rejected
select throws_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-000000007999', 'First', 'Last')$$,
  'P0002', null,
  'nonexistent driver is rejected'
);

-- ===========================================================================
-- Positive Controls
-- ===========================================================================

-- 7. TODA admin successfully updates driver in their own TODA
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c2';

select lives_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d1', 'Juan', 'Dela Cruz', 'Corrected spelling')$$,
  'TODA admin can update driver in their assigned TODA'
);

reset role;

-- 8. Verify profiles updated
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000079d1'),
  'Juan Dela Cruz',
  'driver display_name was updated'
);

select is(
  (select first_name || ' ' || last_name from public.profiles where id = '00000000-0000-0000-0000-0000000079d1'),
  'Juan Dela Cruz',
  'driver first_name and last_name were set'
);

-- 9. Verify audit log entry
select is(
  (select count(*)::int from public.admin_audit_logs
    where target_profile_id = '00000000-0000-0000-0000-0000000079d1'
      and actor_id = '00000000-0000-0000-0000-0000000079c2'
      and action = 'driver.update_name'
      and reason = 'Corrected spelling'),
  1,
  'exactly one audit log row recorded for the update'
);

-- 10. LGU admin successfully updates driver in zone B
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c1';

select lives_ok(
  $$select public.admin_update_driver_name('00000000-0000-0000-0000-0000000079d2', 'Pedro', 'Santos', 'Official name change')$$,
  'LGU admin can update driver in any TODA'
);

reset role;

-- 11. Verify driver 2 profile updated
select is(
  (select display_name from public.profiles where id = '00000000-0000-0000-0000-0000000079d2'),
  'Pedro Santos',
  'driver 2 display_name was updated by LGU admin'
);

-- 12. admin_list_drivers returns widened columns including first_name, last_name, and phone (as LGU admin)
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c1';

select is(
  (select first_name || ' ' || last_name || ' (' || phone || ')'
     from public.admin_list_drivers()
    where driver_id = '00000000-0000-0000-0000-0000000079d1'),
  'Juan Dela Cruz (+639170007904)',
  'admin_list_drivers returns first_name, last_name, and phone'
);

-- 13. admin_list_drivers scopes for TODA admin
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000079c2';

select is(
  (select count(*)::int from public.admin_list_drivers()
    where driver_id in ('00000000-0000-0000-0000-0000000079d1', '00000000-0000-0000-0000-0000000079d2')),
  1,
  'TODA admin only sees driver in their assigned TODA in admin_list_drivers'
);

reset role;

select * from finish();

rollback;
