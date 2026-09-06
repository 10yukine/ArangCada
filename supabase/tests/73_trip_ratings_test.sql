-- pgTAP: trip ratings (bidirectional, persisted, LGU-visible).
--
-- See .pipeline/specs.md Spec 13. Fixture and assertion style mirrors
-- 72_complaints_test.sql, which itself mirrors 60_live_connected_vertical
-- _slice_test.sql's proof shape for sos_reports.

begin;

select plan(11);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000073a1', 'tr-rider@example.test',
   '{"display_name":"TR Rider","mobile_number":"+639170007301"}'::jsonb),
  ('00000000-0000-0000-0000-0000000073b1', 'tr-driver@example.test',
   '{"display_name":"TR Driver","mobile_number":"+639170007302"}'::jsonb),
  ('00000000-0000-0000-0000-0000000073d1', 'tr-stranger@example.test',
   '{"display_name":"TR Stranger","mobile_number":"+639170007303"}'::jsonb),
  ('00000000-0000-0000-0000-0000000073c1', 'tr-lgu-admin@example.test',
   '{"display_name":"TR LGU Admin","mobile_number":"+639170007304"}'::jsonb),
  ('00000000-0000-0000-0000-0000000073c2', 'tr-other-toda-admin@example.test',
   '{"display_name":"TR Other TODA Admin","mobile_number":"+639170007305"}'::jsonb);

update public.profiles set role = 'driver' where id = '00000000-0000-0000-0000-0000000073b1';
update public.profiles set role = 'admin'
 where id in ('00000000-0000-0000-0000-0000000073c1', '00000000-0000-0000-0000-0000000073c2');

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000073c2', 'toda', id
  from public.toda_zones
 where code <> 'CAL-POB-01'
 limit 1;

insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
   rider_display_name, driver_display_name)
values (
  '00000000-0000-0000-0000-0000000073e1',
  '00000000-0000-0000-0000-0000000073a1',
  '00000000-0000-0000-0000-0000000073b1',
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'special', 'completed',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326),
  'Rider', 'Driver'
);

insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
   rider_display_name, driver_display_name)
values (
  '00000000-0000-0000-0000-0000000073e2',
  '00000000-0000-0000-0000-0000000073a1',
  '00000000-0000-0000-0000-0000000073b1',
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'special', 'in_progress',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326),
  'Rider', 'Driver'
);

-- ---------------------------------------------------------------------------
-- Both directions can rate a completed trip
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073a1';

select is(
  (select rater_role from public.submit_trip_rating(
    '00000000-0000-0000-0000-0000000073e1', 5, 'Great, safe ride.')),
  'commuter',
  'the rider can rate the completed trip, role derived server-side'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073b1';

select is(
  (select rater_role from public.submit_trip_rating(
    '00000000-0000-0000-0000-0000000073e1', 4, 'Polite passenger.')),
  'driver',
  'SECURITY: the driver can also rate -- bidirectional, matching the owner''s '
  '5 Sep 2026 decision'
);

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.submit_trip_rating(
      '00000000-0000-0000-0000-0000000073e1', 6, null)$$,
  '22023', null,
  'stars outside 1-5 is refused'
);

select throws_ok(
  $$select public.submit_trip_rating(
      '00000000-0000-0000-0000-0000000073e2', 5, null)$$,
  '22023', null,
  'a trip that is not yet completed cannot be rated'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073d1';

select throws_ok(
  $$select public.submit_trip_rating(
      '00000000-0000-0000-0000-0000000073e1', 5, null)$$,
  '42501', null,
  'SECURITY: only a trip participant may rate it'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073a1';

select throws_ok(
  $$select public.submit_trip_rating(
      '00000000-0000-0000-0000-0000000073e1', 3, 'changed my mind')$$,
  '22023', null,
  'a second rating attempt in the same direction is refused, not upserted'
);

select throws_ok(
  $$select public.submit_trip_rating(
      '00000000-0000-0000-0000-0000000073e1', 5, repeat('x', 241))$$,
  '22023', null,
  'a comment over 240 characters is refused'
);

-- ---------------------------------------------------------------------------
-- RLS: neither party can read what the other wrote about them
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073b1';

select is(
  (select count(*)::integer from public.trip_ratings
    where rater_id = '00000000-0000-0000-0000-0000000073a1'),
  0,
  'SECURITY: the driver cannot select the rider''s rating of them -- matches '
  'the owner''s "LGU-only" comment-visibility decision'
);

select is(
  (select count(*)::integer from public.trip_ratings
    where rater_id = '00000000-0000-0000-0000-0000000073b1'),
  1,
  'but the driver CAN select their own submitted rating'
);

-- ---------------------------------------------------------------------------
-- RLS: admin scoping
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073c1';

select is(
  (select count(*)::integer from public.trip_ratings
    where trip_id = '00000000-0000-0000-0000-0000000073e1'),
  2,
  'an unscoped LGU administrator sees both directions on the trip'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000073c2';

select is(
  (select count(*)::integer from public.trip_ratings
    where trip_id = '00000000-0000-0000-0000-0000000073e1'),
  0,
  'SECURITY: a TODA administrator scoped to a different zone sees nothing '
  'from this trip''s zone'
);

select * from finish();

rollback;
