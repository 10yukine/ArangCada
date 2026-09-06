-- pgTAP: profile photos -- Storage RLS on the profile-photos bucket, and
-- the direct client update of profiles.avatar_path (no RPC; the security
-- boundary is Storage's own RLS, see the migration's header comment).
--
-- See .pipeline/specs.md Spec 15. Fixture/style follows
-- 74_fare_class_claims_test.sql.

begin;

select plan(19);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000075a1', 'pfp-owner@example.test',
   '{"display_name":"PFP Owner","mobile_number":"+639170007501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000075c1', 'pfp-admin@example.test',
   '{"display_name":"PFP Admin","mobile_number":"+639170007502"}'::jsonb),
  ('00000000-0000-0000-0000-0000000075d1', 'pfp-stranger@example.test',
   '{"display_name":"PFP Stranger","mobile_number":"+639170007503"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000075a1', 'commuter', 'PFP Owner',
   '+639170007501', 'pfp-owner@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000075c1', 'admin',    'PFP Admin',
   '+639170007502', 'pfp-admin@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000075d1', 'commuter', 'PFP Stranger',
   '+639170007503', 'pfp-stranger@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

-- Second fixture pair for trip_counterpart_avatar_path()/
-- profile_photos_select_trip_counterpart: a rider (reuses 075a1 above) and
-- a driver, matched on one trip.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000075b1', 'pfp-driver@example.test',
   '{"display_name":"PFP Driver","mobile_number":"+639170007504"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000075b1', 'driver', 'PFP Driver',
   '+639170007504', 'pfp-driver@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

insert into storage.objects (bucket_id, name, owner) values (
  'profile-photos',
  '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg',
  '00000000-0000-0000-0000-0000000075b1'
);

update public.profiles set avatar_path = '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg'
 where id = '00000000-0000-0000-0000-0000000075b1';

insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
   rider_display_name, driver_display_name)
values (
  '00000000-0000-0000-0000-0000000075e1',
  '00000000-0000-0000-0000-0000000075a1',
  '00000000-0000-0000-0000-0000000075b1',
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'special', 'accepted',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326),
  'PFP Owner', 'PFP Driver'
);

-- ---------------------------------------------------------------------------
-- Storage RLS: own-folder write/read, admin read, stranger denied
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'profile-photos',
      '00000000-0000-0000-0000-0000000075a1/photo.jpg',
      '00000000-0000-0000-0000-0000000075a1')$$,
  'a commuter can upload under their own auth.uid() folder'
);

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'profile-photos',
      '00000000-0000-0000-0000-0000000075d1/sneaky.jpg',
      '00000000-0000-0000-0000-0000000075a1')$$,
  '42501', null,
  'SECURITY: a commuter cannot upload into someone else''s folder'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  1,
  'the owner can select their own uploaded photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075d1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  0,
  'SECURITY: a stranger cannot select another commuter''s photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075c1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  1,
  'an admin CAN select a commuter''s uploaded photo'
);

-- ---------------------------------------------------------------------------
-- profiles.avatar_path -- direct client update, no RPC
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select lives_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075a1/photo.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'a commuter can point their own avatar_path at their own uploaded photo'
);

select is(
  (select avatar_path from public.profiles
    where id = '00000000-0000-0000-0000-0000000075a1'),
  '00000000-0000-0000-0000-0000000075a1/photo.jpg',
  'the update actually took'
);

select throws_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075d1/sneaky.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  '23514', null,
  'SECURITY: avatar_path must stay prefixed with the row''s own id, even on '
  'a direct client update with no RPC to check it'
);

-- A stranger's UPDATE naming someone else's row is not a privilege escalation
-- risk here (Storage RLS is the real gate either way), but profiles_update_own
-- should still mean it simply matches zero rows rather than succeeding.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075d1';

select lives_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075d1/photo.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'SECURITY: a stranger targeting someone else''s row by id does not error, '
  'it just matches nothing'
);

-- Switch back to the owner before reading -- profiles_select_own means
-- 075d1 cannot see 075a1's row at all, which would make the next assertion
-- read NULL for the wrong reason (invisible, not unchanged). Same lesson
-- as 74_fare_class_claims_test.sql's `reset role`/identity-switch fix.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select is(
  (select avatar_path from public.profiles
    where id = '00000000-0000-0000-0000-0000000075a1'),
  '00000000-0000-0000-0000-0000000075a1/photo.jpg',
  'SECURITY: ...and the owner''s avatar_path is unchanged by that attempt'
);

-- Composes with the existing display_name/phone grant rather than
-- replacing it -- both columns settable in the same statement.

select lives_ok(
  $$update public.profiles
       set display_name = 'PFP Owner Renamed',
           avatar_path = '00000000-0000-0000-0000-0000000075a1/photo2.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'the new avatar_path grant composes with the existing display_name grant '
  'in a single statement'
);

select throws_ok(
  $$update public.profiles
       set role = 'admin'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  '42501', null,
  'guard_profiles_privileged_columns() still blocks role, unaffected by the '
  'new avatar_path grant'
);

-- ---------------------------------------------------------------------------
-- trip_counterpart_avatar_path() and profile_photos_select_trip_counterpart
-- -- 075a1 (rider) is now at avatar_path .../photo2.jpg, set above.
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select is(
  (select public.trip_counterpart_avatar_path('00000000-0000-0000-0000-0000000075e1')),
  '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg',
  'a rider on an accepted trip can look up their driver''s avatar_path'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg'),
  1,
  'SECURITY: ...and can actually select (sign a URL for) that exact path, '
  'not just learn it from the RPC -- the matching Storage grant is real'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075b1';

select is(
  (select public.trip_counterpart_avatar_path('00000000-0000-0000-0000-0000000075e1')),
  '00000000-0000-0000-0000-0000000075a1/photo2.jpg',
  'and the driver can look up their rider''s avatar_path the same way'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075d1';

select is(
  (select public.trip_counterpart_avatar_path('00000000-0000-0000-0000-0000000075e1')),
  null,
  'SECURITY: a stranger to this trip gets null looking up either party''s '
  'avatar_path -- identical to every other nothing-to-show case, not a '
  'distinguishable exception. Fixed 6 Sep 2026 (later still, cont. VI), '
  'see 20260906040000_trip_counterpart_avatar_no_probe.sql -- the '
  'original raised 42501 here specifically, letting a caller distinguish '
  'not-a-participant from trip-does-not-exist'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg'),
  0,
  'SECURITY: ...and cannot select the driver''s photo object either, even '
  'while the trip is active'
);

-- Once the ride ends, neither the RPC nor the Storage grant should keep
-- exposing either party''s photo to the other -- see this migration''s
-- header for why completed is deliberately excluded from the active window.
reset role;
update public.trips set status = 'completed' where id = '00000000-0000-0000-0000-0000000075e1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select is(
  (select public.trip_counterpart_avatar_path('00000000-0000-0000-0000-0000000075e1')),
  null,
  'once the trip is completed, the same rider no longer gets a path back -- '
  'not an error, just nothing to show, matching an honestly-empty avatar'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075b1/driver-photo.jpg'),
  0,
  'SECURITY: ...and can no longer select the driver''s photo object either, '
  'once the ride that justified the exception has ended'
);

select * from finish();

rollback;
