begin;
select plan(5);

-- A trip still searching for a driver has driver_id NULL. Before
-- 20260928140000 the `<>` participant checks passed for any signed-in user.
insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008301', 'null-driver-rider@example.test', '{"display_name":"Null Driver Rider","mobile_number":"+639170008301"}'),
('00000000-0000-0000-0000-000000008302', 'null-driver-stranger@example.test', '{"display_name":"Null Driver Stranger","mobile_number":"+639170008302"}');

insert into public.trips(id, rider_id, driver_id, status, requested_at, pickup, dropoff) values
('00000000-0000-0000-0000-000000008311', '00000000-0000-0000-0000-000000008301',
 null, 'searching_driver', now() - interval '10 minutes',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));

set local role authenticated;

-- Stranger: not the rider, and there is no driver to be.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008302';
select throws_ok($$select public.cancel_ride('00000000-0000-0000-0000-000000008311')$$,
  '42501', null, 'a stranger cannot cancel a ride that has no driver yet');
select throws_ok($$select public.expire_ride('00000000-0000-0000-0000-000000008311')$$,
  '42501', null, 'a stranger cannot expire a ride that has no driver yet');
select throws_ok($$select public.accept_ride('00000000-0000-0000-0000-000000008311')$$,
  '42501', null, 'a driver-only action fails when no driver is assigned');

-- The rider is unaffected.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008301';
select is((public.cancel_ride('00000000-0000-0000-0000-000000008311')).status::text,
  'cancelled_by_rider', 'the rider can still cancel before a driver is found');

reset role;
select is((select count(*)::int from public.trip_events
            where trip_id = '00000000-0000-0000-0000-000000008311'),
  1, 'only the rider''s cancellation was recorded');

select * from finish();
rollback;
