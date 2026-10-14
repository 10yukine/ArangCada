begin;
select no_plan();
-- Isolate destination rules from the unrelated recurring feedback workflow.
update public.app_evaluation_settings set feedback_interval = 100, repeat_feedback = false where id;

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000010301', 'arrival-admin@example.test', '{"display_name":"Arrival Admin","mobile_number":"+639170010301"}'),
('00000000-0000-0000-0000-000000010302', 'arrival-rider@example.test', '{"display_name":"Arrival Commuter","mobile_number":"+639170010302"}'),
('00000000-0000-0000-0000-000000010303', 'arrival-other@example.test', '{"display_name":"Other Commuter","mobile_number":"+639170010303"}'),
('00000000-0000-0000-0000-000000010304', 'arrival-driver@example.test', '{"display_name":"Arrival Driver","mobile_number":"+639170010304"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000010301';
update public.profiles set role = 'driver' where id = '00000000-0000-0000-0000-000000010304';
insert into public.driver_profiles(id, toda_zone_id, promoted_by, verification_status)
values ('00000000-0000-0000-0000-000000010304',
        (select id from public.toda_zones where code = 'CAL-POB-01'),
        '00000000-0000-0000-0000-000000010301', 'approved');
insert into public.driver_availability(driver_id, toda_zone_id, is_online, latitude, longitude, updated_at)
values ('00000000-0000-0000-0000-000000010304',
        (select id from public.toda_zones where code = 'CAL-POB-01'),
        false, 14.20, 121.16, now() - interval '31 seconds')
on conflict (driver_id) do update
  set latitude = 14.20, longitude = 121.16, updated_at = now() - interval '31 seconds';
insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff, fare_estimate, toda_zone_id)
values ('00000000-0000-0000-0000-000000010310',
        '00000000-0000-0000-0000-000000010302',
        '00000000-0000-0000-0000-000000010304', 'in_progress',
        st_setsrid(st_makepoint(121.16,14.20),4326),
        st_setsrid(st_makepoint(121.17,14.21),4326), 50,
        (select id from public.toda_zones where code = 'CAL-POB-01'));

select ok(has_function_privilege('authenticated',
  'public.rider_reached_destination(uuid,double precision,double precision,double precision)', 'execute'),
  'authenticated can call the RPC');
select ok(not has_function_privilege('anon',
  'public.rider_reached_destination(uuid,double precision,double precision,double precision)', 'execute'),
  'anonymous cannot call the RPC');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010303';
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  '42501', null, 'another commuter cannot report arrival');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010304';
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  '42501', null, 'the driver cannot use commuter arrival');
set local request.jwt.claim.sub = '';
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  '42501', null, 'a null identity cannot report arrival');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010302';
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000099999',14.21,121.17,10)$$,
  '42501', null, 'a missing trip is refused');

select throws_ok(format('select public.rider_reached_destination(%L,%s,%s,%s)',
  '00000000-0000-0000-0000-000000010310', lat, lng, accuracy),
  '22023', null, label)
from (values
  ('14.21','121.17','51','coarse accuracy is refused'),
  ('14.21','121.17','NULL','missing accuracy is refused'),
  ('14.21','121.17','-1','negative accuracy is refused'),
  ('14.21','121.17',quote_literal('NaN'),'NaN accuracy is refused'),
  ('NULL','121.17','10','missing latitude is refused'),
  ('91','121.17','10','invalid latitude is refused'),
  ('14.21','181','10','invalid longitude is refused'),
  ('14.20','121.16','10','a point outside 100 m is refused')
) cases(lat,lng,accuracy,label);
reset role;

update public.trips set status = 'arrived' where id = '00000000-0000-0000-0000-000000010310';
set local role authenticated;
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  '22023', null, 'arrival cannot be reported before a trip starts');
reset role;
update public.trips set status = 'in_progress' where id = '00000000-0000-0000-0000-000000010310';
update public.driver_availability set updated_at = now() - interval '29 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select throws_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  '22023', null, 'fresh driver GPS blocks the fallback');
reset role;
update public.driver_availability set updated_at = now() - interval '31 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select lives_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,50)$$,
  'precise commuter GPS with stale driver GPS starts arrival');
select throws_ok($$select public.complete_trip('00000000-0000-0000-0000-000000010310')$$,
  '22023', null, 'the commuter must wait the full countdown');
select lives_ok($$select public.rider_reached_destination('00000000-0000-0000-0000-000000010310',14.21,121.17,10)$$,
  'a repeated report is idempotent');
reset role;
select is((select completion_available_at from public.trips where id = '00000000-0000-0000-0000-000000010310'),
  now() + interval '60 seconds', 'arrival sets and preserves the 60-second deadline');
select is((select count(*)::int from public.trip_events where trip_id = '00000000-0000-0000-0000-000000010310'
  and event_type = 'ride.destination_radius_entered'), 1, 'only one arrival event is logged');
select ok((select metadata ->> 'source' = 'rider' and (metadata ->> 'distance_m')::float <= 100
  and (select count(*) from jsonb_object_keys(metadata)) = 2
  from public.trip_events where trip_id = '00000000-0000-0000-0000-000000010310'
  and event_type = 'ride.destination_radius_entered'), 'event stores source and distance only');
select ok((select latitude = 14.20 and longitude = 121.16 from public.driver_availability
  where driver_id = '00000000-0000-0000-0000-000000010304'), 'commuter GPS never overwrites driver location');

update public.trips set completion_available_at = now() - interval '1 second'
 where id = '00000000-0000-0000-0000-000000010310';
update public.driver_availability set updated_at = now()
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select throws_ok($$select public.complete_trip('00000000-0000-0000-0000-000000010310')$$,
  '22023', null, 'fresh driver GPS outside 100 m overrides commuter-sourced arrival');
reset role;
update public.driver_availability set updated_at = now() - interval '31 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select is((public.complete_trip('00000000-0000-0000-0000-000000010310')).status::text,
  'completed', 'commuter-sourced arrival and still-stale driver GPS permit completion');
reset role;
select is((select final_fare from public.trips where id = '00000000-0000-0000-0000-000000010310'),
  50::numeric, 'completion retains the locked fare');

-- Driver-sourced arrival does not grant the stale-location exception.
insert into public.trips(id,rider_id,driver_id,status,pickup,dropoff,completion_available_at)
values ('00000000-0000-0000-0000-000000010311',
 '00000000-0000-0000-0000-000000010302','00000000-0000-0000-0000-000000010304','in_progress',
 st_setsrid(st_makepoint(121.16,14.20),4326), st_setsrid(st_makepoint(121.17,14.21),4326), now()-interval '1 second');
update public.trips set toda_zone_id = (select id from public.toda_zones where code = 'CAL-POB-01')
 where id = '00000000-0000-0000-0000-000000010311';
insert into public.trip_events(trip_id,actor_id,event_type)
values ('00000000-0000-0000-0000-000000010311','00000000-0000-0000-0000-000000010304','ride.destination_radius_entered');
update public.driver_availability set updated_at = now()-interval '31 seconds'
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select throws_ok($$select public.complete_trip('00000000-0000-0000-0000-000000010311')$$,
 '22023', null, 'stale far GPS without commuter-sourced arrival still refuses completion');
reset role;
update public.driver_availability set latitude=14.21, longitude=121.17, updated_at=now()
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
select is((public.complete_trip('00000000-0000-0000-0000-000000010311')).status::text,
 'completed', 'fresh driver GPS within 100 m still permits commuter completion');
reset role;

insert into public.trips(id,rider_id,driver_id,status,pickup,dropoff)
values ('00000000-0000-0000-0000-000000010312',
 '00000000-0000-0000-0000-000000010302','00000000-0000-0000-0000-000000010304','in_progress',
 st_setsrid(st_makepoint(121.16,14.20),4326), st_setsrid(st_makepoint(121.17,14.21),4326));
update public.trips set toda_zone_id = (select id from public.toda_zones where code = 'CAL-POB-01')
 where id = '00000000-0000-0000-0000-000000010312';
update public.driver_availability set latitude=14.20, longitude=121.16, updated_at=now()
 where driver_id = '00000000-0000-0000-0000-000000010304';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010304';
select is((public.complete_trip('00000000-0000-0000-0000-000000010312')).status::text,
 'completed', 'driver completion stays unchanged without proximity or countdown');
reset role;
select * from finish();
rollback;
