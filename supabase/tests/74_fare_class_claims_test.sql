-- pgTAP: discount eligibility -- ID photo Storage policies, claim review,
-- and the fare request_ride() actually bills once a claim is approved.
--
-- See .pipeline/specs.md Spec 14. Storage fixture/policy style follows
-- 00_bootstrap_local.sql's storage stub; request_ride() fixture style
-- follows 67_staged_dispatch_radius_test.sql.

begin;

select plan(20);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000074a1', 'fcc-rider@example.test',
   '{"display_name":"FCC Rider","mobile_number":"+639170007401"}'::jsonb),
  ('00000000-0000-0000-0000-0000000074a2', 'fcc-control@example.test',
   '{"display_name":"FCC Control","mobile_number":"+639170007402"}'::jsonb),
  ('00000000-0000-0000-0000-0000000074c1', 'fcc-admin@example.test',
   '{"display_name":"FCC Admin","mobile_number":"+639170007403"}'::jsonb),
  ('00000000-0000-0000-0000-0000000074d1', 'fcc-stranger@example.test',
   '{"display_name":"FCC Stranger","mobile_number":"+639170007404"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000074a1', 'commuter', 'FCC Rider',
   '+639170007401', 'fcc-rider@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000074a2', 'commuter', 'FCC Control',
   '+639170007402', 'fcc-control@example.test',  'active'),
  ('00000000-0000-0000-0000-0000000074c1', 'admin',    'FCC Admin',
   '+639170007403', 'fcc-admin@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000074d1', 'commuter', 'FCC Stranger',
   '+639170007404', 'fcc-stranger@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000074__';

-- ---------------------------------------------------------------------------
-- Storage RLS: own-folder write/read, admin read, stranger denied
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074a1';

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'discount-eligibility-ids',
      '00000000-0000-0000-0000-0000000074a1/id.jpg',
      '00000000-0000-0000-0000-0000000074a1')$$,
  'a commuter can upload under their own auth.uid() folder'
);

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'discount-eligibility-ids',
      '00000000-0000-0000-0000-0000000074d1/sneaky.jpg',
      '00000000-0000-0000-0000-0000000074a1')$$,
  '42501', null,
  'SECURITY: a commuter cannot upload into someone else''s folder'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000074a1/id.jpg'),
  1,
  'the owner can select their own uploaded ID photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074d1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000074a1/id.jpg'),
  0,
  'SECURITY: a stranger cannot select another commuter''s ID photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074c1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000074a1/id.jpg'),
  1,
  'an admin CAN select a commuter''s submitted ID photo, to review it'
);

-- ---------------------------------------------------------------------------
-- submit_fare_class_claim()
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074a1';

select throws_ok(
  $$select public.submit_fare_class_claim('astronaut',
      '00000000-0000-0000-0000-0000000074a1/id.jpg')$$,
  '22023', null,
  'an unrecognised fare class is refused'
);

select throws_ok(
  $$select public.submit_fare_class_claim('student',
      '00000000-0000-0000-0000-0000000074d1/not-mine.jpg')$$,
  '42501', null,
  'SECURITY: a claim cannot reference a photo path outside the caller''s own folder'
);

select is(
  (select status from public.submit_fare_class_claim('student',
      '00000000-0000-0000-0000-0000000074a1/id.jpg')),
  'pending_review',
  'a valid claim is filed as pending_review'
);

select throws_ok(
  $$select public.submit_fare_class_claim('senior_citizen',
      '00000000-0000-0000-0000-0000000074a1/id2.jpg')$$,
  '22023', null,
  'a second pending claim from the same commuter is refused'
);

select is(
  (select claimant_display_name from public.fare_class_claims
    where profile_id = '00000000-0000-0000-0000-0000000074a1'),
  'FCC Rider',
  'the claim denormalizes the claimant''s display name at submission time, '
  'same idiom as complaints/trip_ratings -- admin_web reads it with no join'
);

-- ---------------------------------------------------------------------------
-- review_fare_class_claim()
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074d1';

select throws_ok(
  $$select public.review_fare_class_claim(
      (select id from public.fare_class_claims where profile_id = '00000000-0000-0000-0000-0000000074a1'),
      true, null)$$,
  '42501', null,
  'SECURITY: a non-admin cannot review a claim'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074c1';

select throws_ok(
  $$select public.review_fare_class_claim(
      (select id from public.fare_class_claims where profile_id = '00000000-0000-0000-0000-0000000074a1'),
      false, null)$$,
  '22023', null,
  'rejecting without a reason is refused'
);

select is(
  (select fare_class::text from public.profiles
    where id = '00000000-0000-0000-0000-0000000074a1'),
  'standard',
  'baseline: the rider is still billed standard before any approval'
);

select is(
  (select status from public.review_fare_class_claim(
      (select id from public.fare_class_claims where profile_id = '00000000-0000-0000-0000-0000000074a1'),
      true, null)),
  'approved',
  'an admin can approve a pending claim'
);

select is(
  (select fare_class::text from public.profiles
    where id = '00000000-0000-0000-0000-0000000074a1'),
  'discounted',
  'approval actually flips profiles.fare_class -- this is the line that '
  'makes the approval mean something, not just a status label'
);

select is(
  (select count(*)::integer from public.admin_audit_logs
    where action = 'fare_class_claim.approved'
      and target_profile_id = '00000000-0000-0000-0000-0000000074a1'),
  1,
  'the approval wrote exactly one admin_audit_logs row'
);

select throws_ok(
  $$select public.review_fare_class_claim(
      (select id from public.fare_class_claims where profile_id = '00000000-0000-0000-0000-0000000074a1'),
      false, 'changed my mind')$$,
  '22023', null,
  'an already-decided claim cannot be re-decided'
);

-- ---------------------------------------------------------------------------
-- THE FULL LOOP: request_ride() actually bills the discounted rate
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074a1';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'fcc-key-discounted')$$,
  'the approved (discounted) rider can book'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000074a2';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'fcc-key-standard')$$,
  'a rider with no approved claim (still standard) can book the same route'
);

-- Both trips now exist, one owned by each rider. trips_select_participant
-- restricts a plain SELECT to rows where the caller is the rider or driver,
-- so comparing both fare_estimate values needs a caller who can see both --
-- reset role escapes the impersonation the same way every other cross-rider
-- verification in this suite does (see 67_staged_dispatch_radius_test.sql).
reset role;

select ok(
  (select fare_estimate from public.trips where idempotency_key = 'fcc-key-discounted')
  <
  (select fare_estimate from public.trips where idempotency_key = 'fcc-key-standard'),
  'THE POINT OF THIS FEATURE: for the identical distance, the approved '
  'rider''s booking is billed strictly less than the standard rider''s -- '
  'the discount is not just a flag nothing reads'
);

select * from finish();

rollback;
