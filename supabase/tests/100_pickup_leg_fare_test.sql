-- 20261008090000: a driver from beyond the free distance adds the metres past
-- it to the trip's, and the fare is read once from the ordinance table. A
-- driver inside the free distance adds nothing. The driver's distance is
-- recorded either way.
--
--   CAL-CAN-01    lon 121.050-121.080, lat 14.170-14.200
--   pickup        14.185, 121.0724
--   destination   14.172, 121.0520   about 2.6 km from the pickup (3 km fare)
--   near driver   14.185, 121.0687   about 0.4 km from the pickup
--   far driver    14.185, 121.0557   about 1.8 km from the pickup
--
-- Everything fails on the schema before the migration.
begin;
select plan(17);

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
select is(
  public.get_mobile_settings() - 'min_mobile_build' - 'routing' - 'search',
  '{"pickup_free_m": 0, "pickup_charge_max_m": 0}'::jsonb,
  'the app is told there is no pickup charge while it is off');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.0687);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-off');
reset role;

select results_eq(
  $$select status::text, fare_estimate, pickup_fare
      from public.trips where idempotency_key = 'pl-off'$$,
  $$values ('driver_assigned', 68::numeric, null::numeric)$$,
  'switched off, an assigned trip is billed for the trip alone');
select ok(
  (select pickup_distance_m between 300 and 500 from public.trips where idempotency_key = 'pl-off'),
  'the driver''s distance to the pickup is recorded even while the charge is off');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.decline_ride((select id from public.trips where idempotency_key = 'pl-off'));
reset role;

-- Switched on.
update public.mobile_settings set charge_pickup_leg = true;
select is(
  public.get_mobile_settings() - 'min_mobile_build' - 'routing' - 'search',
  '{"pickup_free_m": 600, "pickup_charge_max_m": 2400}'::jsonb,
  'the app is told the free distance and the most that can be billed beyond it');

-- A driver inside the free distance.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.0687);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-near');
reset role;

select is(
  (select status::text from public.trips where idempotency_key = 'pl-near'),
  'driver_assigned', 'the booking reaches the near driver');
select results_eq(
  $$select fare_estimate, pickup_fare from public.trips where idempotency_key = 'pl-near'$$,
  $$values (68::numeric, 0::numeric)$$,
  'a driver inside the free distance adds nothing');

-- The completed trip is charged what was offered.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.accept_ride((select id from public.trips where idempotency_key = 'pl-near'));
reset role;
update public.trips set status = 'in_progress' where idempotency_key = 'pl-near';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.complete_trip((select id from public.trips where idempotency_key = 'pl-near'));
reset role;
select is(
  (select final_fare from public.trips where idempotency_key = 'pl-near'),
  68::numeric, 'the completed trip is charged the trip fare');

-- A driver 1.8 km away is found only once the search has widened.
delete from public.driver_feedback_obligations
 where driver_id = '00000000-0000-0000-0000-0000000100b1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-far');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.0557);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.retry_dispatch((select id from public.trips where idempotency_key = 'pl-far'));
reset role;
select results_eq(
  $$select status::text, pickup_distance_m, fare_estimate
      from public.trips where idempotency_key = 'pl-far'$$,
  $$values ('searching_driver', null::integer, 68::numeric)$$,
  'while nobody is assigned the trip carries its own fare');

update public.trips set requested_at = now() - interval '4 minutes'
 where idempotency_key = 'pl-far';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.retry_dispatch((select id from public.trips where idempotency_key = 'pl-far'));
reset role;

select is(
  (select status::text from public.trips where idempotency_key = 'pl-far'),
  'driver_assigned', 'the widened search reaches the far driver');
select ok(
  (select pickup_distance_m between 1700 and 1900 from public.trips where idempotency_key = 'pl-far'),
  'the far driver''s whole distance is recorded');
select is(
  (select fare_estimate from public.trips where idempotency_key = 'pl-far'),
  (select public.compute_fare(distance_m + pickup_distance_m - 600, 'special', 'standard', 1)
     from public.trips where idempotency_key = 'pl-far'),
  'the fare is one lookup on the trip plus the metres beyond the free distance');
select results_eq(
  $$select fare_estimate, pickup_fare from public.trips where idempotency_key = 'pl-far'$$,
  $$values (76::numeric, 8::numeric)$$,
  'about 2.6 km plus about 1.2 km billed is the 4 km fare, 8 pesos more');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.accept_ride((select id from public.trips where idempotency_key = 'pl-far'));
reset role;
select is(
  (select fare_estimate from public.trips where idempotency_key = 'pl-far'),
  76::numeric, 'accepting leaves the fare as it was offered');

-- The completed trip is charged the total, and a later change to its driver
-- column (account deletion clears it) must not reprice it.
update public.trips set status = 'in_progress' where idempotency_key = 'pl-far';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.complete_trip((select id from public.trips where idempotency_key = 'pl-far'));
reset role;
update public.trips set driver_id = null where idempotency_key = 'pl-far';
select results_eq(
  $$select final_fare, fare_estimate, pickup_fare from public.trips where idempotency_key = 'pl-far'$$,
  $$values (76::numeric, 76::numeric, 8::numeric)$$,
  'the completed trip is charged the total and keeps it when its driver is removed');

-- The free distance is the owner's number: with none, the near driver's
-- 0.4 km is billed (about 2.6 + 0.4 km is the 4 km fare).
delete from public.driver_feedback_obligations
 where driver_id = '00000000-0000-0000-0000-0000000100b1';
update public.mobile_settings set pickup_free_m = 0;
select is(
  public.get_mobile_settings() - 'min_mobile_build' - 'routing' - 'search',
  '{"pickup_free_m": 0, "pickup_charge_max_m": 3000}'::jsonb,
  'the app follows a changed free distance');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true, 14.185, 121.0687);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.request_ride(14.185, 121.0724, 14.172, 121.052, 'Pickup', 'Destination', 'pl-zero');
reset role;
select results_eq(
  $$select status::text, fare_estimate, pickup_fare
      from public.trips where idempotency_key = 'pl-zero'$$,
  $$values ('driver_assigned', 76::numeric, 8::numeric)$$,
  'and so does the bill');

set local role authenticated;
select throws_ok($$ update public.mobile_settings set pickup_free_m = 5000 $$,
  '42501', null, 'no account can change the charge through the API');
reset role;

select * from finish();
rollback;
