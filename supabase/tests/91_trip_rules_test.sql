-- 20261002100000 (suspension, cancelling a started trip) and the daily
-- trip-place purge of 20260930120000, which had no test.
begin;
select plan(20);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000009101', 'tr-admin@example.test',   '{"display_name":"TR Admin","mobile_number":"+639170009101"}'),
('00000000-0000-0000-0000-000000009111', 'tr-rider1@example.test',  '{"display_name":"TR Rider One","mobile_number":"+639170009111"}'),
('00000000-0000-0000-0000-000000009112', 'tr-rider2@example.test',  '{"display_name":"TR Rider Two","mobile_number":"+639170009112"}'),
('00000000-0000-0000-0000-000000009113', 'tr-rider3@example.test',  '{"display_name":"TR Rider Three","mobile_number":"+639170009113"}'),
('00000000-0000-0000-0000-000000009114', 'tr-rider4@example.test',  '{"display_name":"TR Rider Four","mobile_number":"+639170009114"}'),
('00000000-0000-0000-0000-000000009121', 'tr-driver1@example.test', '{"display_name":"TR Driver One","mobile_number":"+639170009121"}'),
('00000000-0000-0000-0000-000000009122', 'tr-driver2@example.test', '{"display_name":"TR Driver Two","mobile_number":"+639170009122"}'),
('00000000-0000-0000-0000-000000009123', 'tr-driver3@example.test', '{"display_name":"TR Driver Three","mobile_number":"+639170009123"}'),
('00000000-0000-0000-0000-000000009124', 'tr-driver4@example.test', '{"display_name":"TR Driver Four","mobile_number":"+639170009124"}');

update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000009101';
insert into public.admin_scopes (admin_id, scope)
values ('00000000-0000-0000-0000-000000009101', 'lgu');
update public.profiles set role = 'driver' where id::text like '%-00000000912_';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status)
select p.id, (select id from public.toda_zones where code = 'CAL-POB-01'),
       '00000000-0000-0000-0000-000000009101', 'approved'
  from public.profiles p where p.id::text like '%-00000000912_';

insert into public.driver_availability (driver_id, toda_zone_id, is_online, latitude, longitude)
select d.id, d.toda_zone_id, false, 14.2160, 121.1660
  from public.driver_profiles d where d.id::text like '%-00000000912_'
on conflict (driver_id) do nothing;
-- Driver four is idle and online.
update public.driver_availability set is_online = true
 where driver_id = '00000000-0000-0000-0000-000000009124';

-- One driver per stage: offered, accepted, in progress.
insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff, pickup_label, destination_label) values
('00000000-0000-0000-0000-000000009131', '00000000-0000-0000-0000-000000009111',
 '00000000-0000-0000-0000-000000009121', 'driver_assigned',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326), 'Home', 'Market'),
('00000000-0000-0000-0000-000000009132', '00000000-0000-0000-0000-000000009112',
 '00000000-0000-0000-0000-000000009122', 'accepted',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326), 'Home', 'Market'),
('00000000-0000-0000-0000-000000009133', '00000000-0000-0000-0000-000000009113',
 '00000000-0000-0000-0000-000000009123', 'in_progress',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326), 'Home', 'Market');

update public.trips set toda_zone_id = (select id from public.toda_zones where code = 'CAL-POB-01')
 where id::text like '%-00000000913_';

-- A started trip cannot be cancelled by the rider. ----------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009113';
select throws_ok($$select public.cancel_ride('00000000-0000-0000-0000-000000009133')$$,
  '22023', null, 'a rider cannot cancel a trip that has started');
reset role;
select is((select status::text from public.trips where id = '00000000-0000-0000-0000-000000009133'),
  'in_progress', 'the trip is still in progress');

-- Suspension. ---------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009101';
select lives_ok($$
  select public.admin_set_profile_status(id, 'suspended', 'test suspension')
    from public.profiles where id::text like '%-00000000912_'$$,
  'an admin suspends the four drivers');
reset role;

select is((select status::text from public.trips where id = '00000000-0000-0000-0000-000000009131'),
  'no_driver_available', 'an unanswered offer to a suspended driver is closed');
select is((select status::text from public.trips where id = '00000000-0000-0000-0000-000000009132'),
  'cancelled_by_driver', 'a ride the driver had accepted but not started is cancelled');
select is((select cancellation_reason from public.trips where id = '00000000-0000-0000-0000-000000009132'),
  'driver_suspended', 'with a reason that says who ended it');
select is((select status::text from public.trips where id = '00000000-0000-0000-0000-000000009133'),
  'in_progress', 'a trip already in progress is left to finish');
select is((select count(*)::int from public.driver_availability
            where driver_id::text like '%-00000000912_' and is_online),
  0, 'every suspended driver is offline');
select is((select count(*)::int from public.trip_events
            where trip_id in ('00000000-0000-0000-0000-000000009131', '00000000-0000-0000-0000-000000009132')
              and metadata ->> 'reason' = 'driver_suspended'
              and actor_id = '00000000-0000-0000-0000-000000009101'),
  2, 'both releases are recorded against the administrator');

-- The released rider can book again straight away.
select is((select count(*)::int from public.trips
            where rider_id = '00000000-0000-0000-0000-000000009112'
              and status in ('requested', 'searching_driver', 'driver_assigned', 'accepted',
                             'driver_en_route', 'arrived', 'in_progress', 'emergency_reported')),
  0, 'the released rider holds no live trip');

-- The driver with a passenger on board can finish, and nothing else.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009123';
select is((public.complete_trip('00000000-0000-0000-0000-000000009133')).status::text,
  'completed', 'the suspended driver can still complete the trip in progress');
reset role;

-- If a suspension and an accept cross, the trip cannot move on.
insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff) values
('00000000-0000-0000-0000-000000009134', '00000000-0000-0000-0000-000000009114',
 '00000000-0000-0000-0000-000000009124', 'accepted',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009124';
select throws_ok($$select public.mark_arrived('00000000-0000-0000-0000-000000009134')$$,
  '42501', null, 'a suspended driver cannot report arrival');
reset role;
update public.trips set status = 'arrived' where id = '00000000-0000-0000-0000-000000009134';
set local role authenticated;
select throws_ok($$select public.start_trip('00000000-0000-0000-0000-000000009134')$$,
  '42501', null, 'or start the trip');
reset role;

-- The lock order that removes the completion deadlock.
select ok(
  pg_get_functiondef('public.publish_driver_location(uuid,double precision,double precision,double precision)'::regprocedure)
    like '%from public.trips where id = p_trip_id for no key update;%',
  'publish_driver_location takes the trip before the availability row');

-- purge_trip_places (20260930120000). -----------------------------------------
update public.trips set completed_at = now() - interval '31 days', updated_at = now() - interval '31 days'
 where id = '00000000-0000-0000-0000-000000009133';
update public.trips set updated_at = now() - interval '31 days'
 where id = '00000000-0000-0000-0000-000000009131';

select ok(not has_function_privilege('authenticated', 'public.purge_trip_places(interval)', 'execute')
      and not has_function_privilege('anon', 'public.purge_trip_places(interval)', 'execute'),
  'app users cannot run the purge');
select is(public.purge_trip_places(), 2, 'the purge clears the two trips that ended over 30 days ago');
select is((select pickup_label || '/' || destination_label from public.trips
            where id = '00000000-0000-0000-0000-000000009133'),
  'Pickup/Destination', 'their place names are gone');
select ok((select pickup_lat is null and destination_lat is null from public.trips
            where id = '00000000-0000-0000-0000-000000009133'),
  'and so are their coordinates');
select is((select pickup_label from public.trips where id = '00000000-0000-0000-0000-000000009132'),
  'Home', 'a trip that ended today keeps its places');
select is(public.purge_trip_places(), 0, 'running it again changes nothing');

select * from finish();
rollback;
