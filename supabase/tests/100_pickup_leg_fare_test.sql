-- 20261008090000: the driver's way to the pickup is added to the trip's
-- kilometres and the fare is read once from the ordinance table.
--
--   CAL-CAN-01   lon 121.050-121.080, lat 14.170-14.200
--   driver       14.185, 121.0650
--   pickup       14.185, 121.0724   about 800 m east of the driver
--   destination  14.172, 121.0520   about 2.6 km from the pickup (3 km fare)
--
-- Everything from "switched on" down fails on the schema before the migration.
begin;
select plan(13);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000100a1', 'pl-rider@example.test',
   '{"display_name":"PL Rider","mobile_number":"+639170010001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000100b1', 'pl-driver@example.test',
   '{"display_name":"PL Driver","mobile_number":"+639170010002"}'::jsonb);

update public.profiles
   set role = case when id::text like '%b_' then 'driver' else 'commuter' end::public.user_role,
       status = 'active',
       phone_verified_at = now()
 where id::text like '%-0000000100__';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status)
values ('00000000-0000-0000-0000-0000000100b1',
        (select id from public.toda_zones where code = 'CAL-CAN-01'),
        '00000000-0000-0000-0000-0000000100a1', 'approved')
on conflict (id) do nothing;

insert into public.driver_documents (driver_id, document_type, storage_path, status)
select '00000000-0000-0000-0000-0000000100b1', required.dt, 'test/' || required.dt::text, 'approved'
  from unnest(public.driver_required_document_types()) required(dt);

-- Switched off, which is how the migration leaves it.
select is(public.get_mobile_settings() -> 'pickup_charge_max_m', '0'::jsonb,
  'the app is told there is no pickup charge while it is off');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.065);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-off');
reset role;

select results_eq(
  $$select status::text, pickup_distance_m, pickup_fare, fare_estimate
      from public.trips where idempotency_key = 'pl-off'$$,
  $$values ('driver_assigned', null::integer, null::numeric, 68::numeric)$$,
  'switched off, an assigned trip is billed for the trip alone');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.decline_ride((select id from public.trips where idempotency_key = 'pl-off'));
reset role;

-- Switched on.
update public.mobile_settings set charge_pickup_leg = true;
select is(public.get_mobile_settings() -> 'pickup_charge_max_m', '3000'::jsonb,
  'the app is told the farthest a driver can be, which bounds the charge');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.065);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-on');
reset role;

select is(
  (select status::text from public.trips where idempotency_key = 'pl-on'),
  'driver_assigned', 'the booking reaches the driver');
select ok(
  (select pickup_distance_m between 700 and 900 from public.trips where idempotency_key = 'pl-on'),
  'the driver''s distance to the pickup is recorded');
select is(
  (select fare_estimate from public.trips where idempotency_key = 'pl-on'),
  (select public.compute_fare(distance_m + pickup_distance_m, 'special', 'standard', 1)
     from public.trips where idempotency_key = 'pl-on'),
  'the fare is one lookup on the combined distance');
select results_eq(
  $$select fare_estimate, pickup_fare from public.trips where idempotency_key = 'pl-on'$$,
  $$values (76::numeric, 8::numeric)$$,
  'about 2.6 km plus about 0.8 km is the 4 km fare, 8 pesos more than the trip alone');

-- Accepting changes nothing, and the completed trip is charged the total.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.accept_ride((select id from public.trips where idempotency_key = 'pl-on'));
reset role;
select is(
  (select fare_estimate from public.trips where idempotency_key = 'pl-on'),
  76::numeric, 'accepting leaves the fare as it was offered');
update public.trips set status = 'in_progress' where idempotency_key = 'pl-on';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.complete_trip((select id from public.trips where idempotency_key = 'pl-on'));
reset role;
select is(
  (select final_fare from public.trips where idempotency_key = 'pl-on'),
  76::numeric, 'the completed trip is charged the total');

-- No driver at first; one comes online and the retry assigns them.
delete from public.driver_feedback_obligations
 where driver_id = '00000000-0000-0000-0000-0000000100b1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-retry');
reset role;
select results_eq(
  $$select status::text, pickup_distance_m, fare_estimate
      from public.trips where idempotency_key = 'pl-retry'$$,
  $$values ('searching_driver', null::integer, 68::numeric)$$,
  'while nobody is assigned the trip carries its own fare');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.065);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.retry_dispatch((select id from public.trips where idempotency_key = 'pl-retry'));
reset role;
select results_eq(
  $$select status::text, fare_estimate, pickup_fare
      from public.trips where idempotency_key = 'pl-retry'$$,
  $$values ('driver_assigned', 76::numeric, 8::numeric)$$,
  'a driver found on a retry adds the pickup leg too');

-- A later change to the driver column of a finished trip (account deletion
-- clears it) must not reprice the trip.
update public.trips set driver_id = null where idempotency_key = 'pl-on';
select results_eq(
  $$select final_fare, fare_estimate, pickup_fare from public.trips where idempotency_key = 'pl-on'$$,
  $$values (76::numeric, 76::numeric, 8::numeric)$$,
  'a finished trip keeps its fare when its driver is removed');

set local role authenticated;
select throws_ok($$ update public.mobile_settings set charge_pickup_leg = false $$,
  '42501', null, 'no account can switch the charge through the API');
reset role;

select * from finish();
rollback;
