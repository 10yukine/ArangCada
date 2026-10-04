-- 20261004120000: a waiting driver may be anywhere in the service area, and
-- the nearest eligible driver gets the ride whatever their TODA.
--
--   CAL-POB-01   lon 121.150-121.180, lat 14.200-14.230   the driver's TODA
--   CAL-CAN-01   lon 121.050-121.080, lat 14.170-14.200   where the driver waits
--   DEV-SJVTODA-CABUYAO                                   developer-test zone
--
-- "another TODA's area" and "books in another TODA's area" fail on the schema
-- before that migration.
begin;
select plan(7);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000095a1', 'oa-rider@example.test',
   '{"display_name":"OA Rider","mobile_number":"+639170009501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000095b1', 'oa-driver@example.test',
   '{"display_name":"OA Driver","mobile_number":"+639170009502"}'::jsonb);

update public.profiles
   set role = case when id::text like '%b_' then 'driver' else 'commuter' end::public.user_role,
       status = 'active',
       phone_verified_at = now()
 where id::text like '%-0000000095__';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status)
values ('00000000-0000-0000-0000-0000000095b1',
        (select id from public.toda_zones where code = 'CAL-POB-01'),
        '00000000-0000-0000-0000-0000000095a1', 'approved')
on conflict (id) do nothing;

insert into public.driver_documents (driver_id, document_type, storage_path, status)
select '00000000-0000-0000-0000-0000000095b1', required.dt, 'test/' || required.dt::text, 'approved'
  from unnest(public.driver_required_document_types()) required(dt);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000095b1';

select lives_ok(
  $$select public.set_driver_availability(true, 14.185, 121.065)$$,
  'a driver may wait in another TODA''s area');
select throws_ok(
  $$select public.set_driver_availability(true, 14.40, 121.30)$$,
  '22023',
  'an online driver must be inside the Calamba service area and belong to an active TODA',
  'a driver outside every zone is still refused');
select throws_ok(
  $$select public.set_driver_availability(true, 14.2825, 121.115)$$,
  '22023', null,
  'a developer-test zone does not count for an ordinary driver');
select throws_ok(
  $$select public.set_driver_availability(true, null, null)$$,
  '22023', null, 'a location is still required');

-- The driver's own TODA is switched off.
reset role;
update public.toda_zones set is_active = false where code = 'CAL-POB-01';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000095b1';
select throws_ok(
  $$select public.set_driver_availability(true, 14.185, 121.065)$$,
  '22023', null, 'a driver whose own TODA is inactive stays offline');
reset role;
update public.toda_zones set is_active = true where code = 'CAL-POB-01';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000095a1';
select is(
  (select driver_id from public.request_ride(14.1855, 121.066, 14.190, 121.070,
      'Pickup', 'Destination', 'oa-key-1')),
  '00000000-0000-0000-0000-0000000095b1'::uuid,
  'a rider who books in another TODA''s area gets the nearest driver');
reset role;
select is(
  (select z.code from public.trips t join public.toda_zones z on z.id = t.toda_zone_id
    where t.idempotency_key = 'oa-key-1'),
  'CAL-CAN-01', 'and the trip still records the pickup''s TODA');

select * from finish();
rollback;
