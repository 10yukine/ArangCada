-- pgTAP: staged dispatch search radius (Calamba City Hall decision, 2026-08-31).
--
-- WHY THIS FILE EXISTS
--
-- 20260831090000 removed the TODA filter from candidate selection, which left
-- the scan unbounded: the nearest driver in the WHOLE CITY wins, even one
-- 12 km away. 20260831100000 bounds it -- 1 km first, widening to 3 km after
-- an interval, then giving up.
--
-- 66_nearest_driver_dispatch_test cannot catch a regression here. Its fixture
-- puts both drivers within ~2 km of the pickup, so a build that ignored the
-- radius entirely would still pass every assertion in that file. This one is
-- built so the radius is the ONLY thing that can produce the expected answer.
--
-- Geometry (1 degree of latitude ~ 110 574 m at this latitude):
--
--   pickup      14.2150, 121.1650
--   NEARBY      14.2160, 121.1650   ~  111 m   inside 1 km
--   MIDRANGE    14.2331, 121.1650   ~ 2 000 m   outside 1 km, inside 3 km
--   DISTANT     14.2512, 121.1650   ~ 4 000 m   outside 3 km
--
-- Longitude is held constant so the distances are pure latitude arithmetic and
-- a reader can verify them without trusting PostGIS.

begin;

select plan(13);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000067a1', 'sr-rider@example.test',
   '{"display_name":"SR Rider","mobile_number":"+639170006701"}'::jsonb),
  ('00000000-0000-0000-0000-0000000067b1', 'sr-midrange@example.test',
   '{"display_name":"SR Midrange","mobile_number":"+639170006702"}'::jsonb),
  ('00000000-0000-0000-0000-0000000067b2', 'sr-distant@example.test',
   '{"display_name":"SR Distant","mobile_number":"+639170006703"}'::jsonb),
  ('00000000-0000-0000-0000-0000000067c1', 'sr-outsider@example.test',
   '{"display_name":"SR Outsider","mobile_number":"+639170006704"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000067a1', 'commuter', 'SR Rider',
   '+639170006701', 'sr-rider@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000067b1', 'driver',   'SR Midrange',
   '+639170006702', 'sr-midrange@example.test', 'active'),
  ('00000000-0000-0000-0000-0000000067b2', 'driver',   'SR Distant',
   '+639170006703', 'sr-distant@example.test',  'active'),
  ('00000000-0000-0000-0000-0000000067c1', 'commuter', 'SR Outsider',
   '+639170006704', 'sr-outsider@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

-- Phone verification (added 31 Aug 2026). can_driver_go_online() and
-- request_ride() now require a verified mobile number, so every fixture
-- account has to be verified or the assertions below fail for a reason that
-- has nothing to do with what they are testing. 69_phone_verification_test.sql
-- is what covers the gate itself.
update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000067__';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status) values
  ('00000000-0000-0000-0000-0000000067b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000067a1', 'approved'),
  ('00000000-0000-0000-0000-0000000067b2',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000067a1', 'approved')
on conflict (id) do nothing;

-- Dispatch fixtures satisfy the required-document gate.
insert into public.driver_documents (driver_id, document_type, storage_path, status)
select d.id, required.dt, 'test/' || required.dt::text, 'approved'
from public.driver_profiles d
cross join unnest(public.driver_required_document_types()) required(dt)
where d.id::text like '%-0000000067__';


-- ---------------------------------------------------------------------------
-- The settings row
-- ---------------------------------------------------------------------------
select is(
  (select initial_radius_m from public.dispatch_settings where id),
  1000,
  'the initial search radius defaults to the 1 km City Hall asked for'
);

select is(
  (select widened_radius_m from public.dispatch_settings where id),
  3000,
  'the widened search radius defaults to 3 km'
);

select is(
  (select count(*)::integer from public.dispatch_settings),
  1,
  'dispatch_settings holds exactly one row -- it is a settings singleton'
);

-- ---------------------------------------------------------------------------
-- ONLY a midrange driver is online: too far for the first pass
-- ---------------------------------------------------------------------------
insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000067b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2331, 121.1650)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000067a1';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'sr-key-0001')$$,
  'the booking is accepted even when nobody is within the first-pass radius'
);

select is(
  (select driver_id from public.trips where idempotency_key = 'sr-key-0001'),
  null::uuid,
  'a driver 2 km away is NOT assigned on the first pass -- this is the '
  'assertion that fails if the radius is ignored'
);

select is(
  (select status::text from public.trips where idempotency_key = 'sr-key-0001'),
  'searching_driver',
  'the trip waits in searching_driver rather than failing outright'
);

-- Retrying immediately must NOT widen. The widening is earned by elapsed time
-- on the server; a client that simply calls retry_dispatch in a tight loop
-- must not be able to buy itself a bigger radius.
select is(
  (select driver_id from public.retry_dispatch(
     (select id from public.trips where idempotency_key = 'sr-key-0001'))),
  null::uuid,
  'retrying immediately does not widen the radius -- a spamming client cannot '
  'shortcut the interval'
);

-- ---------------------------------------------------------------------------
-- After the interval, the same driver becomes reachable
-- ---------------------------------------------------------------------------
reset role;

-- Backdate the request rather than sleeping: the rule is "now() - requested_at
-- >= widen_after_seconds", so moving requested_at into the past is equivalent
-- and keeps the suite fast.
update public.trips
   set requested_at = now() - interval '10 minutes'
 where idempotency_key = 'sr-key-0001';

select is(
  public.dispatch_radius_m(now() - interval '10 minutes'),
  3000,
  'a trip that has been searching past the interval earns the widened radius'
);

select is(
  public.dispatch_radius_m(now()),
  1000,
  'a trip that has just been created is still on the narrow radius'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000067a1';

select is(
  (select driver_id from public.retry_dispatch(
     (select id from public.trips where idempotency_key = 'sr-key-0001'))),
  '00000000-0000-0000-0000-0000000067b1'::uuid,
  'once widened to 3 km the 2 km driver IS assigned'
);

-- ---------------------------------------------------------------------------
-- A driver beyond the widened radius is never reachable
-- ---------------------------------------------------------------------------
reset role;

update public.trips
   set status = 'completed', completed_at = now()
 where idempotency_key = 'sr-key-0001';

-- Midrange goes offline; only the 4 km driver remains.
update public.driver_availability set is_online = false
 where driver_id = '00000000-0000-0000-0000-0000000067b1';

insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000067b2',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2512, 121.1650)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000067a1';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'sr-key-0002')$$,
  'a booking with only a far-away driver online is still accepted'
);

reset role;
update public.trips
   set requested_at = now() - interval '10 minutes'
 where idempotency_key = 'sr-key-0002';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000067a1';

select is(
  (select status::text from public.retry_dispatch(
     (select id from public.trips where idempotency_key = 'sr-key-0002'))),
  'no_driver_available',
  'a driver 4 km away is never assigned; the commuter is told honestly instead '
  'of being left on a spinner forever'
);

-- ---------------------------------------------------------------------------
-- Only an LGU admin may retune dispatch
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000067c1';

-- The UPDATE does not error: RLS makes the row invisible to a non-admin, so the
-- statement succeeds against zero rows. Asserting on the VALUE afterwards is
-- what actually proves nothing changed -- a throws_ok here would pass even if
-- the policy were missing entirely.
update public.dispatch_settings set widened_radius_m = 45000 where id;

select is(
  (select widened_radius_m from public.dispatch_settings where id),
  3000,
  'an ordinary commuter cannot widen the city-wide dispatch radius -- the '
  'update silently affects no rows and the setting is unchanged'
);

reset role;

select * from finish();

rollback;
