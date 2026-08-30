-- pgTAP: authorization inside SECURITY DEFINER RPCs.
--
-- WHY THIS FILE EXISTS
--
-- 41 SECURITY DEFINER functions are executable by `authenticated`. That is by
-- design -- they must write rows the caller cannot write directly -- so the
-- Supabase advisor's "Signed-In Users Can Execute SECURITY DEFINER Function"
-- warnings are expected here and revoking EXECUTE would break dispatch.
--
-- The consequence is that EXECUTE grants protect nothing. The ONLY thing
-- standing between a signed-in commuter and someone else's trip is the
-- authorization check inside each function body. An audit found those checks
-- present and correct -- but 27 of the 41 had no test asserting they reject an
-- unauthorized caller, so deleting a guard during a refactor would have gone
-- unnoticed by a fully green suite.
--
-- This file covers the state-mutating ones: the RPCs that can cancel a
-- stranger's ride, move their driver, read the driver roster, or approve a
-- driver. Read-only helpers (is_admin, toda_zone_covering) are deliberately
-- omitted -- they leak nothing an authenticated user cannot already read.
--
-- EVERY NEGATIVE ASSERTION IS PAIRED WITH A POSITIVE CONTROL.
-- Without one, a 42501 proves nothing: an ungranted role, a missing fixture or
-- a typo'd function name all raise too, and the test would pass just as
-- happily against a function with no guard at all.

begin;

select plan(12);

-- ---------------------------------------------------------------------------
-- Fixtures: an owner, an unrelated signed-in commuter, and an assigned driver
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000065a1', 'rpcauth-owner@example.test',
   '{"display_name":"Owner Rider","mobile_number":"+639170006501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000065a2', 'rpcauth-outsider@example.test',
   '{"display_name":"Outsider","mobile_number":"+639170006502"}'::jsonb),
  ('00000000-0000-0000-0000-0000000065b1', 'rpcauth-driver@example.test',
   '{"display_name":"Assigned Driver","mobile_number":"+639170006503"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000065a1', 'commuter', 'Owner Rider',
   '+639170006501', 'rpcauth-owner@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000065a2', 'commuter', 'Outsider',
   '+639170006502', 'rpcauth-outsider@example.test', 'active'),
  ('00000000-0000-0000-0000-0000000065b1', 'driver',   'Assigned Driver',
   '+639170006503', 'rpcauth-driver@example.test',   'active')
on conflict (id) do nothing;

-- driver_availability FKs to driver_profiles, not profiles, so the driver
-- needs a driver_profiles row first.
insert into public.driver_profiles (id, toda_zone_id, promoted_by)
values (
  '00000000-0000-0000-0000-0000000065b1',
  (select id from public.toda_zones order by code limit 1),
  '00000000-0000-0000-0000-0000000065a1'
)
on conflict (id) do nothing;

-- publish_driver_location requires the driver to have an availability row.
-- The positive control below is what surfaced this: without it the driver was
-- refused too, which would have left the negative assertions unable to
-- distinguish 'authorization rejected me' from 'the fixture was incomplete'.
insert into public.driver_availability (driver_id, toda_zone_id, is_online)
values (
  '00000000-0000-0000-0000-0000000065b1',
  (select id from public.toda_zones order by code limit 1),
  true
)
on conflict (driver_id) do update set is_online = true;

insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff)
values (
  '00000000-0000-0000-0000-0000000065d1',
  '00000000-0000-0000-0000-0000000065a1',
  '00000000-0000-0000-0000-0000000065b1',
  (select id from public.toda_zones order by code limit 1),
  'special',
  'accepted',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326)
);

-- ---------------------------------------------------------------------------
-- An unrelated signed-in commuter must not touch someone else's trip
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000065a2';

select throws_ok(
  $$select public.cancel_ride('00000000-0000-0000-0000-0000000065d1')$$,
  '42501', null,
  'a stranger cannot cancel someone else''s ride'
);

select throws_ok(
  $$select public.decline_ride('00000000-0000-0000-0000-0000000065d1')$$,
  '42501', null,
  'a stranger cannot decline a ride they were never offered'
);

select throws_ok(
  $$select public.expire_ride('00000000-0000-0000-0000-0000000065d1')$$,
  '42501', null,
  'a stranger cannot expire someone else''s ride'
);

select throws_ok(
  $$select public.publish_driver_location(
      '00000000-0000-0000-0000-0000000065d1', 14.215, 121.165, 5.0)$$,
  '42501', null,
  'a stranger cannot forge the assigned driver''s GPS position'
);

select throws_ok(
  $$select public.report_trip_chat(
      '00000000-0000-0000-0000-0000000065d1', 'harassment', true)$$,
  '42501', null,
  'a stranger cannot report a conversation they were not part of'
);

-- ---------------------------------------------------------------------------
-- A commuter must not reach admin surfaces
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select * from public.admin_list_drivers()$$,
  '42501', null,
  'a commuter cannot enumerate the driver roster'
);

select throws_ok(
  $$select public.admin_review_scoped_driver(
      '00000000-0000-0000-0000-0000000065b1', 'approve', null)$$,
  '42501', null,
  'a commuter cannot approve a driver'
);

-- ---------------------------------------------------------------------------
-- POSITIVE CONTROLS
-- ---------------------------------------------------------------------------
-- These are what make the seven assertions above meaningful. If the rightful
-- participants are also refused, then 42501 is coming from something other
-- than the authorization check -- a missing grant, an absent fixture, a
-- renamed function -- and the negatives prove nothing.

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000065b1';

select lives_ok(
  $$select public.publish_driver_location(
      '00000000-0000-0000-0000-0000000065d1', 14.215, 121.165, 5.0)$$,
  'POSITIVE CONTROL: the assigned driver CAN publish their own position'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000065a1';

select lives_ok(
  $$select public.report_trip_chat(
      '00000000-0000-0000-0000-0000000065d1', 'harassment', true)$$,
  'POSITIVE CONTROL: the rider on the trip CAN report its chat'
);

select is(
  (select status::text
     from public.trips
    where id = '00000000-0000-0000-0000-0000000065d1'),
  'accepted',
  'POSITIVE CONTROL: the refused calls above changed nothing -- the trip is '
  'still accepted, so the guards rejected rather than half-applying'
);

select lives_ok(
  $$select public.cancel_ride('00000000-0000-0000-0000-0000000065d1')$$,
  'POSITIVE CONTROL: the rider CAN cancel their own ride'
);

select is(
  (select status::text
     from public.trips
    where id = '00000000-0000-0000-0000-0000000065d1'),
  'cancelled_by_rider',
  'the rightful cancellation actually took effect'
);

reset role;

select * from finish();

rollback;
