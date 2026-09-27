-- pgTAP: nearest-driver dispatch (Calamba City Hall decision, 2026-08-31).
--
-- WHY THIS FILE EXISTS
--
-- 20260831090000 changed how request_ride picks a driver: candidates are no
-- longer restricted to the pickup's TODA, and they are ordered by real distance
-- instead of by most-recent heartbeat.
--
-- The entire existing suite passed unchanged across that edit, including
-- assertion 22 of 60_live_connected_vertical_slice_test, which is literally
-- named "dispatch assigns the approved same-TODA driver server-side". It kept
-- passing because its fixture has exactly one online driver, so same-TODA and
-- nearest happen to be the same answer. Nothing in the suite could tell the two
-- rules apart, which means the change shipped uncovered until this file.
--
-- The setup below is built so the two rules give OPPOSITE answers:
--
--   pickup            (121.165, 14.215)  inside CAL-POB-01
--   driver FAR-SAME   registered CAL-POB-01, parked at the far corner
--   driver NEAR-OTHER registered CAL-CAN-01, currently beside the pickup
--
-- Old rule picks FAR-SAME (same TODA). New rule picks NEAR-OTHER (nearer).
-- A Canlubang driver sitting in Poblacion is an ordinary situation, not a
-- contrived one -- it is exactly the case City Hall asked us to stop refusing.

begin;

select plan(8);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000066a1', 'nd-rider@example.test',
   '{"display_name":"ND Rider","mobile_number":"+639170006601"}'::jsonb),
  ('00000000-0000-0000-0000-0000000066b1', 'nd-far-same@example.test',
   '{"display_name":"Far Same TODA","mobile_number":"+639170006602"}'::jsonb),
  ('00000000-0000-0000-0000-0000000066b2', 'nd-near-other@example.test',
   '{"display_name":"Near Other TODA","mobile_number":"+639170006603"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000066a1', 'commuter', 'ND Rider',
   '+639170006601', 'nd-rider@example.test',      'active'),
  ('00000000-0000-0000-0000-0000000066b1', 'driver',   'Far Same TODA',
   '+639170006602', 'nd-far-same@example.test',   'active'),
  ('00000000-0000-0000-0000-0000000066b2', 'driver',   'Near Other TODA',
   '+639170006603', 'nd-near-other@example.test', 'active')
-- handle_new_user() already created these rows from auth metadata, defaulting
-- role to 'commuter'. DO NOTHING would silently keep that, and
-- can_driver_go_online() requires role='driver' -- the drivers would be
-- invisible to dispatch for a reason nothing in the test surfaces.
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

-- Phone verification (added 31 Aug 2026). can_driver_go_online() and
-- request_ride() now require a verified mobile number, so every fixture
-- account has to be verified or the assertions below fail for a reason that
-- has nothing to do with what they are testing. 69_phone_verification_test.sql
-- is what covers the gate itself.
update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000066__';

-- verification_status must be 'approved': can_driver_go_online() requires it,
-- and an unapproved driver is silently invisible to dispatch.
insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status) values
  ('00000000-0000-0000-0000-0000000066b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000066a1', 'approved'),
  ('00000000-0000-0000-0000-0000000066b2',
   (select id from public.toda_zones where code = 'CAL-CAN-01'),
   '00000000-0000-0000-0000-0000000066a1', 'approved')
on conflict (id) do nothing;

-- Dispatch fixtures satisfy the required-document gate.
insert into public.driver_documents (driver_id, document_type, storage_path, status)
select d.id, required.dt, 'test/' || required.dt::text, 'approved'
from public.driver_profiles d
cross join unnest(public.driver_required_document_types()) required(dt)
where d.id::text like '%-0000000066__';


-- FAR-SAME sits in the pickup's own TODA but at the opposite corner (~2 km).
-- NEAR-OTHER belongs to Canlubang but is parked ~150 m from the pickup.
insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000066b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2290, 121.1790),
  ('00000000-0000-0000-0000-0000000066b2',
   (select id from public.toda_zones where code = 'CAL-CAN-01'),
   true, 14.2160, 121.1660)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

-- Sanity: the fixture really does pit the two rules against each other.
select is(
  (select count(*) from public.driver_availability
    where driver_id in ('00000000-0000-0000-0000-0000000066b1',
                        '00000000-0000-0000-0000-0000000066b2')
      and is_online),
  2::bigint,
  'fixture: both drivers are online, so the choice between them is real'
);

select ok(
  (select toda_zone_id from public.driver_availability
    where driver_id = '00000000-0000-0000-0000-0000000066b2')
  <> (select id from public.toda_zones where code = 'CAL-POB-01'),
  'fixture: the nearer driver belongs to a DIFFERENT TODA than the pickup'
);

-- ---------------------------------------------------------------------------
-- The dispatch decision
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000066a1';

select lives_ok(
  $$select public.request_ride(
      14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'nd-key-0001')$$,
  'a booking succeeds with no same-TODA driver requirement'
);

select is(
  (select driver_id from public.trips where idempotency_key = 'nd-key-0001'),
  '00000000-0000-0000-0000-0000000066b2'::uuid,
  'the NEARER driver wins even though he belongs to another TODA -- under the '
  'old jurisdiction rule this ride would have gone to the far same-TODA driver'
);

select is(
  (select status::text from public.trips where idempotency_key = 'nd-key-0001'),
  'driver_assigned',
  'the trip is actually assigned, not left searching'
);

-- Governance must survive the change: the trip still belongs to the pickup's
-- TODA for admin scoping and per-TODA reporting, even though the driver is
-- registered elsewhere.
select is(
  (select toda_zone_id from public.trips where idempotency_key = 'nd-key-0001'),
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'trips.toda_zone_id still records the PICKUP TODA, so admin scoping and '
  'per-TODA reporting are unaffected'
);

-- ---------------------------------------------------------------------------
-- Causation: move the far driver closer and the winner must flip
-- ---------------------------------------------------------------------------
-- Without this the assertion above would also pass if dispatch were ordering by
-- something unrelated that happened to favour the second driver.
reset role;

-- Close the first trip: trips_one_active_per_rider (from the original schema)
-- correctly refuses a second live booking for the same commuter, so the rider
-- has to finish one before the causation check can run.
update public.trips
   set status = 'completed', completed_at = now()
 where idempotency_key = 'nd-key-0001';

update public.driver_availability
   set is_online = true, latitude = 14.2151, longitude = 121.1651
 where driver_id = '00000000-0000-0000-0000-0000000066b1';
update public.driver_availability
   set is_online = true
 where driver_id = '00000000-0000-0000-0000-0000000066b2';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000066a1';

select lives_ok(
  $$select public.request_ride(
      14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'nd-key-0002')$$,
  'a second booking succeeds'
);

select is(
  (select driver_id from public.trips where idempotency_key = 'nd-key-0002'),
  '00000000-0000-0000-0000-0000000066b1'::uuid,
  'CAUSATION: moving the other driver nearest flips the assignment, proving '
  'distance decides rather than TODA, insertion order or heartbeat recency'
);

reset role;

select * from finish();

rollback;
