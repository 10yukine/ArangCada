begin;
select plan(13);

-- Each trip needs its own rider and driver: one active trip per person.
insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008201', 'cancel-rider1@example.test', '{"display_name":"Cancel Rider One","mobile_number":"+639170008201"}'),
('00000000-0000-0000-0000-000000008202', 'cancel-driver1@example.test', '{"display_name":"Cancel Driver One","mobile_number":"+639170008202"}'),
('00000000-0000-0000-0000-000000008203', 'cancel-rider2@example.test', '{"display_name":"Cancel Rider Two","mobile_number":"+639170008203"}'),
('00000000-0000-0000-0000-000000008204', 'cancel-driver2@example.test', '{"display_name":"Cancel Driver Two","mobile_number":"+639170008204"}'),
('00000000-0000-0000-0000-000000008205', 'cancel-rider3@example.test', '{"display_name":"Cancel Rider Three","mobile_number":"+639170008205"}'),
('00000000-0000-0000-0000-000000008206', 'cancel-driver3@example.test', '{"display_name":"Cancel Driver Three","mobile_number":"+639170008206"}'),
('00000000-0000-0000-0000-000000008207', 'cancel-rider4@example.test', '{"display_name":"Cancel Rider Four","mobile_number":"+639170008207"}'),
('00000000-0000-0000-0000-000000008208', 'cancel-driver4@example.test', '{"display_name":"Cancel Driver Four","mobile_number":"+639170008208"}');

insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff) values
('00000000-0000-0000-0000-000000008211', '00000000-0000-0000-0000-000000008201',
 '00000000-0000-0000-0000-000000008202', 'accepted',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326)),
('00000000-0000-0000-0000-000000008212', '00000000-0000-0000-0000-000000008203',
 '00000000-0000-0000-0000-000000008204', 'in_progress',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326)),
('00000000-0000-0000-0000-000000008213', '00000000-0000-0000-0000-000000008205',
 '00000000-0000-0000-0000-000000008206', 'accepted',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326)),
('00000000-0000-0000-0000-000000008214', '00000000-0000-0000-0000-000000008207',
 '00000000-0000-0000-0000-000000008208', 'driver_assigned',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));

set local role authenticated;

-- Driver one, trip still at pickup.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008202';
select throws_ok($$select public.cancel_ride('00000000-0000-0000-0000-000000008211')$$,
  '42501', null, 'drivers can no longer cancel without a reason');
select throws_ok($$select public.cancel_ride_as_driver('00000000-0000-0000-0000-000000008211', null)$$,
  '22023', null, 'a reason is required');
select throws_ok($$select public.cancel_ride_as_driver('00000000-0000-0000-0000-000000008211', 'changed my mind')$$,
  '22023', null, 'only the listed reasons are accepted');
select is((public.cancel_ride_as_driver('00000000-0000-0000-0000-000000008211', 'passenger_no_show')).status::text,
  'cancelled_by_driver', 'driver cancel before the trip starts succeeds');

-- Driver two, trip already started.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008204';
select throws_ok($$select public.cancel_ride_as_driver('00000000-0000-0000-0000-000000008212', 'passenger_no_show')$$,
  '22023', null, 'a started trip cannot be cancelled by the driver');

-- Rider three.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008205';
select throws_ok($$select public.cancel_ride_as_driver('00000000-0000-0000-0000-000000008213', 'passenger_no_show')$$,
  '42501', null, 'a rider cannot use the driver cancel');
select is((public.cancel_ride('00000000-0000-0000-0000-000000008213')).status::text,
  'cancelled_by_rider', 'riders still cancel with cancel_ride');

-- Driver four declines an offer: allowed, and not a cancellation.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008208';
select is((public.decline_ride('00000000-0000-0000-0000-000000008214')).status::text,
  'no_driver_available', 'declining an offer ends it like an expired offer');

reset role;
select is((select count(*)::int from public.trip_events
            where trip_id = '00000000-0000-0000-0000-000000008214'
              and event_type = 'ride.declined'),
  1, 'the decline is logged as a decline');
select is((select cancellation_reason from public.trips where id = '00000000-0000-0000-0000-000000008214'),
  null, 'a decline is never recorded as a cancellation');
select is((select cancellation_reason from public.trips where id = '00000000-0000-0000-0000-000000008211'),
  'passenger_no_show', 'the reason is stored on the trip for admin review');
select is((select metadata->>'reason' from public.trip_events
            where trip_id = '00000000-0000-0000-0000-000000008211'
              and event_type = 'ride.cancelled_by_driver'),
  'passenger_no_show', 'the cancellation is recorded as a reviewable event');
select is((select cancellation_reason from public.trips where id = '00000000-0000-0000-0000-000000008213'),
  'cancelled_by_rider', 'rider cancellation reason is unchanged');

select * from finish();
rollback;
