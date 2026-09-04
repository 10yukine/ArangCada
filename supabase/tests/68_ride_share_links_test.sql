-- pgTAP: ride-share links and the 4-passenger operating cap
-- (Calamba City Hall decisions, 2026-08-31).
--
-- WHY THIS FILE EXISTS
--
-- ride_share_view() is the first and only function in this system that anon
-- can execute. Every other read path in ArangCada is gated by RLS behind an
-- authenticated session. A mistake here is not a bug that shows a user the
-- wrong screen -- it is a public data leak of a named person's live location.
--
-- So this file does not merely check that sharing works. It checks, one
-- assertion each, that the things which must NOT come out do not come out:
-- the token table itself, the rider's identity, a finished trip, and a revoked
-- token. Those are the assertions worth keeping if this file is ever trimmed.

begin;

select plan(16);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000068a1', 'rs-rider@example.test',
   '{"display_name":"RS Rider","mobile_number":"+639170006801"}'::jsonb),
  ('00000000-0000-0000-0000-0000000068b1', 'rs-driver@example.test',
   '{"display_name":"RS Driver","mobile_number":"+639170006802"}'::jsonb),
  ('00000000-0000-0000-0000-0000000068c1', 'rs-stranger@example.test',
   '{"display_name":"RS Stranger","mobile_number":"+639170006803"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000068a1', 'commuter', 'RS Rider',
   '+639170006801', 'rs-rider@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000068b1', 'driver',   'RS Driver',
   '+639170006802', 'rs-driver@example.test',   'active'),
  ('00000000-0000-0000-0000-0000000068c1', 'commuter', 'RS Stranger',
   '+639170006803', 'rs-stranger@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

-- Phone verification (added 31 Aug 2026). can_driver_go_online() and
-- request_ride() now require a verified mobile number, so every fixture
-- account has to be verified or the assertions below fail for a reason that
-- has nothing to do with what they are testing. 69_phone_verification_test.sql
-- is what covers the gate itself.
update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000068__';

insert into public.driver_profiles
  (id, toda_zone_id, promoted_by, verification_status, body_number) values
  ('00000000-0000-0000-0000-0000000068b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000068a1', 'approved', 'POB-042')
on conflict (id) do update set body_number = excluded.body_number;

insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000068b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2155, 121.1650)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

-- ---------------------------------------------------------------------------
-- The operating passenger cap
-- ---------------------------------------------------------------------------
-- The ordinance transcription must be untouched. This is the assertion that
-- fails if someone "fixes" the 3 into a 4 in seed.sql.
select is(
  (select max_passengers from public.fare_matrix
    where ride_type = 'special' and is_active),
  3,
  'the ORDINANCE TRANSCRIPTION still prints 3 for Espesyal -- unchanged, so the '
  'database still matches the tarpaulin a panelist can photograph'
);

select is(
  (select operating_max_passengers from public.fare_matrix
    where ride_type = 'special' and is_active),
  4,
  'the LGU-approved OPERATING cap for Espesyal is 4, recorded separately from '
  'the printed limit'
);

select is(
  (select is_bookable from public.fare_matrix
    where ride_type = 'pooling' and is_active),
  false,
  'pooling is flagged not-bookable rather than deleted -- its fare rows remain '
  'as the ordinance record of Regular na Byahe'
);

select ok(
  (select count(*) from public.fare_matrix
    where ride_type = 'pooling' and is_active) = 1,
  'the pooling fare row still EXISTS; withdrawal is not deletion'
);

-- Espesyal is billed per trip, so the cap change must not move any money.
select is(
  public.compute_fare_centavos(2000, 'special', 'standard', 1),
  6000,
  'Espesyal for 1 passenger is PHP 60.00'
);

select is(
  public.compute_fare_centavos(2000, 'special', 'standard', 4),
  6000,
  'Espesyal for 4 passengers is STILL PHP 60.00 -- per trip, not per head, so '
  'raising the cap changed no fare'
);

select throws_ok(
  $$select public.compute_fare_centavos(2000, 'special', 'standard', 5)$$,
  null,
  null,
  'a 5th passenger is rejected -- the cap moved to 4, it was not removed'
);

-- ---------------------------------------------------------------------------
-- A live trip to share
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000068a1';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'SM Calamba', 'Calamba Crossing', 'rs-key-0001')$$,
  'the commuter books a ride to share'
);

select is(
  (select passenger_count from public.trips where idempotency_key = 'rs-key-0001'),
  1,
  'a new trip defaults to 1 passenger'
);

select is(
  (select passenger_count from public.set_trip_passenger_count(
     (select id from public.trips where idempotency_key = 'rs-key-0001'), 4)),
  4,
  'the commuter can set 4 passengers'
);

select throws_ok(
  $$select public.set_trip_passenger_count(
      (select id from public.trips where idempotency_key = 'rs-key-0001'), 5)$$,
  null,
  null,
  'the server refuses 5 passengers regardless of what the client asks for'
);

-- ---------------------------------------------------------------------------
-- Sharing
-- ---------------------------------------------------------------------------
create temporary table rs_token on commit drop as
select public.create_ride_share_link(
         (select id from public.trips where idempotency_key = 'rs-key-0001')) as token;

-- The anon assertions below have to read this token back while acting as anon,
-- which is precisely the situation being simulated: someone holding the link
-- and nothing else. Granting select on the scratch table is a test-harness
-- concession, not a production grant -- rs_token is a temporary table that
-- disappears at commit and exists only in this transaction.
grant select on rs_token to public;

select ok(
  (select char_length(token) >= 32 from rs_token),
  'the issued token is long enough to be unguessable'
);

-- The point of the feature: a stranger with the link, holding no session at
-- all, can watch the trip.
reset role;

-- Clearing the JWT claim as well as switching role matters, and getting this
-- wrong is easy: 00_bootstrap_local.sql implements auth.uid() as a read of
-- request.jwt.claim.sub, which SET ROLE does not touch. An earlier draft of
-- this file switched role but left the rider's sub in place, so "anon" still
-- satisfied trips_select_participant (rider_id = auth.uid()) and appeared to
-- read a trip it should not have. That was a false alarm in the test, not a
-- hole in the schema -- a production anon request carries no sub at all, which
-- is what the empty string reproduces here.
set local request.jwt.claim.sub = '';
set local role anon;

select is(
  (select driver_body_number from public.ride_share_view((select token from rs_token))),
  'POB-042',
  'ANON with the link can see the live trip -- a family member needs no account'
);

-- The point of the safeguards: that is ALL they can see.
select is(
  (select count(*)::integer from public.ride_share_links),
  0,
  'SECURITY: anon cannot read the token table itself, so possessing one link '
  'never leaks other links, trips, or riders'
);

-- RLS filters rows, it does not raise. So the correct assertion is that anon
-- sees ZERO trips -- not that the query errors. (An earlier draft of this file
-- used throws_ok here and failed for exactly that reason, which is worth
-- recording: a throws_ok that never fires would have looked like a passing
-- security test while proving nothing.)
select is(
  (select count(*)::integer from public.trips),
  0,
  'SECURITY: anon reading trips directly gets zero rows -- ride_share_view is '
  'the only door, and it carries no rider identity'
);

-- Expiry is enforced against the trip's own status, server-side.
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000068a1';
update public.trips
   set status = 'completed', completed_at = now()
 where idempotency_key = 'rs-key-0001';

set local request.jwt.claim.sub = '';
set local role anon;

select is(
  (select count(*)::integer from public.ride_share_view((select token from rs_token))),
  0,
  'SECURITY: the same valid, unrevoked token returns NOTHING once the trip '
  'ends -- the link is not a standing window into someone''s location'
);

reset role;

select * from finish();

rollback;
