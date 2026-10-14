begin;
select no_plan();
-- Isolate the proximity rules from the unrelated recurring feedback workflow.
update public.app_evaluation_settings set feedback_interval = 100, repeat_feedback = false where id;

-- One commuter and one driver per trip: each may hold only one live trip.
-- Trip 51: accepted, the commuter confirms.   Trip 52: in progress, the commuter stops early.
-- Trip 53: accepted, driver GPS only.         Trip 54: in progress, driver GPS only.
insert into auth.users(id, email, raw_user_meta_data)
select ('00000000-0000-0000-0000-0000000105' || n)::uuid, 'step-' || n || '@example.test',
       jsonb_build_object('display_name', 'Step ' || n, 'mobile_number', '+6391700105' || n)
  from unnest(array['01', '11', '12', '13', '14', '21', '22', '23', '24']) as n;
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000010501';
update public.profiles set role = 'driver' where id::text like '%-00000001052_';
insert into public.driver_profiles(id, toda_zone_id, promoted_by, verification_status)
select p.id, (select id from public.toda_zones where code = 'CAL-POB-01'),
       '00000000-0000-0000-0000-000000010501', 'approved'
  from public.profiles p where p.id::text like '%-00000001052_';
-- Every driver starts far away (about 11 km) with current GPS.
insert into public.driver_availability(driver_id, toda_zone_id, is_online, latitude, longitude, updated_at)
select d.id, d.toda_zone_id, false, 14.25, 121.25, now()
  from public.driver_profiles d where d.id::text like '%-00000001052_'
on conflict (driver_id) do update set latitude = 14.25, longitude = 121.25, updated_at = now();

-- Pickup at (14.20, 121.16) and drop-off at (14.21, 121.17), about 1.5 km apart.
insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff, fare_estimate, toda_zone_id)
select ('00000000-0000-0000-0000-0000000105' || v.n)::uuid,
       ('00000000-0000-0000-0000-0000000105' || v.rider)::uuid,
       ('00000000-0000-0000-0000-0000000105' || v.driver)::uuid,
       v.status::public.trip_status,
       st_setsrid(st_makepoint(121.16, 14.20), 4326),
       st_setsrid(st_makepoint(121.17, 14.21), 4326), 50,
       (select id from public.toda_zones where code = 'CAL-POB-01')
  from (values ('51', '11', '21', 'accepted'), ('52', '12', '22', 'in_progress'),
               ('53', '13', '23', 'accepted'), ('54', '14', '24', 'in_progress'))
       as v(n, rider, driver, status);

select ok(has_function_privilege('authenticated', 'public.rider_confirm_pickup(uuid)', 'execute'),
  'authenticated can confirm the driver is here');
select ok(not has_function_privilege('anon', 'public.rider_confirm_pickup(uuid)', 'execute'),
  'anonymous cannot confirm the driver is here');
select ok(has_function_privilege('authenticated', 'public.rider_request_stop(uuid)', 'execute'),
  'authenticated can ask to stop');
select ok(not has_function_privilege('anon', 'public.rider_request_stop(uuid)', 'execute'),
  'anonymous cannot ask to stop');

-- The commuter's confirmations: theirs alone, and only at the right stage.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010521';
select throws_ok($$select public.rider_confirm_pickup('00000000-0000-0000-0000-000000010551')$$,
  '42501', null, 'the driver cannot confirm on the commuter''s behalf');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010522';
select throws_ok($$select public.rider_request_stop('00000000-0000-0000-0000-000000010552')$$,
  '42501', null, 'the driver cannot ask to stop on the commuter''s behalf');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010512';
select throws_ok($$select public.rider_confirm_pickup('00000000-0000-0000-0000-000000010552')$$,
  '22023', null, 'a started trip cannot be confirmed at pickup');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010511';
select throws_ok($$select public.rider_request_stop('00000000-0000-0000-0000-000000010551')$$,
  '22023', null, 'a stop cannot be requested before the trip starts');
select ok((public.rider_confirm_pickup('00000000-0000-0000-0000-000000010551')).rider_confirmed_pickup_at is not null,
  'the commuter confirms the driver is here');
select lives_ok($$select public.rider_confirm_pickup('00000000-0000-0000-0000-000000010551')$$,
  'confirming twice is harmless');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010512';
select ok((public.rider_request_stop('00000000-0000-0000-0000-000000010552')).rider_requested_stop_at is not null,
  'the commuter asks to stop here');
select lives_ok($$select public.rider_request_stop('00000000-0000-0000-0000-000000010552')$$,
  'asking twice is harmless');
reset role;
select is((select count(*)::int from public.trip_events
  where trip_id in ('00000000-0000-0000-0000-000000010551', '00000000-0000-0000-0000-000000010552')
    and event_type in ('ride.rider_confirmed_pickup', 'ride.rider_requested_stop')), 2,
  'each confirmation is logged once');

-- Arrival at the pickup point.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010523';
select throws_ok($$select public.mark_arrived('00000000-0000-0000-0000-000000010553')$$,
  '22023', null, 'a driver far from the pin cannot mark arrival');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010521';
select is((public.mark_arrived('00000000-0000-0000-0000-000000010551')).status::text, 'arrived',
  'the commuter''s confirmation allows arrival away from the pin');
reset role;
update public.driver_availability set latitude = 14.2003, longitude = 121.1603,
  updated_at = now() - interval '31 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010523';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010523';
select throws_ok($$select public.mark_arrived('00000000-0000-0000-0000-000000010553')$$,
  '22023', null, 'GPS older than 30 seconds does not count, even at the pin');
reset role;
update public.driver_availability set latitude = 14.2012, longitude = 121.16, updated_at = now()
 where driver_id = '00000000-0000-0000-0000-000000010523';
set local role authenticated;
select throws_ok($$select public.mark_arrived('00000000-0000-0000-0000-000000010553')$$,
  '22023', null, 'about 130 m from the pin is too far');
reset role;
update public.driver_availability set latitude = 14.2008, longitude = 121.16, updated_at = now()
 where driver_id = '00000000-0000-0000-0000-000000010523';
set local role authenticated;
select is((public.mark_arrived('00000000-0000-0000-0000-000000010553')).status::text, 'arrived',
  'about 90 m from the pin with current GPS allows arrival');
reset role;

-- Completion at the drop-off point (the driver's path; the commuter's is in 103).
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010524';
select throws_ok($$select public.complete_trip('00000000-0000-0000-0000-000000010554')$$,
  '22023', null, 'a driver far from the drop-off cannot complete');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010522';
select is((public.complete_trip('00000000-0000-0000-0000-000000010552')).status::text, 'completed',
  'the commuter''s request to stop allows completion away from the drop-off');
reset role;
select is((select final_fare from public.trips where id = '00000000-0000-0000-0000-000000010552'),
  50::numeric, 'an early stop keeps the quoted fare');
update public.driver_availability set latitude = 14.21, longitude = 121.17,
  updated_at = now() - interval '31 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010524';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010524';
select throws_ok($$select public.complete_trip('00000000-0000-0000-0000-000000010554')$$,
  '22023', null, 'GPS older than 30 seconds does not count at the drop-off either');
reset role;
update public.driver_availability set updated_at = now()
 where driver_id = '00000000-0000-0000-0000-000000010524';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010524';
select is((public.complete_trip('00000000-0000-0000-0000-000000010554')).status::text, 'completed',
  'current GPS at the drop-off allows completion');
reset role;

select * from finish();
rollback;
