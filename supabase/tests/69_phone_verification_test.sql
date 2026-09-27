-- pgTAP: phone (SMS OTP) verification gates.
--
-- WHY THIS FILE EXISTS
--
-- The verify screen in the Flutter app is a convenience. If verification were
-- only enforced there, anyone who could reach the Supabase REST endpoint with a
-- valid session -- which is anyone who can read the anon key out of the APK --
-- could book, drive, and mint public tracking links without ever proving they
-- hold the SIM. CLAUDE.md rule 6 exists for exactly this, and these assertions
-- are what make it true rather than aspirational.
--
-- Each gate gets an assertion in BOTH directions: refused while unverified,
-- allowed once verified. A one-directional test would pass against a build
-- that had accidentally broken the feature for everyone.

begin;

select plan(16);

-- ---------------------------------------------------------------------------
-- Fixtures: one unverified commuter, one verified commuter, one internal
-- tester, and a driver to dispatch.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000069a1', 'pv-unverified@example.test',
   '{"display_name":"PV Unverified","mobile_number":"+639170006901"}'::jsonb),
  ('00000000-0000-0000-0000-0000000069a2', 'pv-verified@example.test',
   '{"display_name":"PV Verified","mobile_number":"+639170006902"}'::jsonb),
  ('00000000-0000-0000-0000-0000000069b1', 'pv-driver@example.test',
   '{"display_name":"PV Driver","mobile_number":"+639170006903"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000069a1', 'commuter', 'PV Unverified',
   '+639170006901', 'pv-unverified@example.test', 'active'),
  ('00000000-0000-0000-0000-0000000069a2', 'commuter', 'PV Verified',
   '+639170006902', 'pv-verified@example.test',   'active'),
  ('00000000-0000-0000-0000-0000000069b1', 'driver',   'PV Driver',
   '+639170006903', 'pv-driver@example.test',     'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status) values
  ('00000000-0000-0000-0000-0000000069b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000069a1', 'approved')
on conflict (id) do nothing;

-- Dispatch fixtures satisfy the required-document gate.
insert into public.driver_documents (driver_id, document_type, storage_path, status)
select d.id, required.dt, 'test/' || required.dt::text, 'approved'
from public.driver_profiles d
cross join unnest(public.driver_required_document_types()) required(dt)
where d.id::text like '%-0000000069__';


-- ---------------------------------------------------------------------------
-- The trigger, not a manual UPDATE
-- ---------------------------------------------------------------------------
-- Setting phone_confirmed_at on auth.users is what Supabase does when an OTP
-- is accepted. profiles.phone_verified_at must follow on its own -- if the app
-- had to write it, the client would be deciding its own verification state.
select is(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000069a2'),
  null,
  'a new account starts unverified'
);

update auth.users
   set phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000069a2';

select isnt(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000069a2'),
  null,
  'confirming the phone on auth.users mirrors into profiles BY TRIGGER -- the '
  'client never writes its own verification state'
);

select is(
  public.is_verified_account('00000000-0000-0000-0000-0000000069a1'),
  false,
  'is_verified_account is false for the unverified commuter'
);

select is(
  public.is_verified_account('00000000-0000-0000-0000-0000000069a2'),
  true,
  'is_verified_account is true once the phone is confirmed'
);

-- ---------------------------------------------------------------------------
-- Gate 1: booking
-- ---------------------------------------------------------------------------
update auth.users set phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000069b1';

insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000069b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2155, 121.1650)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000069a1';

select throws_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'pv-key-0001')$$,
  '42501',
  null,
  'SECURITY: an unverified commuter CANNOT book, no matter what the app shows'
);

select is(
  (select count(*)::integer from public.trips where idempotency_key = 'pv-key-0001'),
  0,
  'the refused booking created no trip row -- it failed closed'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000069a2';

select lives_ok(
  $$select public.request_ride(
      14.2150, 121.1650, 14.2200, 121.1700,
      'Pickup', 'Destination', 'pv-key-0002')$$,
  'a verified commuter books normally -- the gate blocks the unverified, not '
  'everyone'
);

-- ---------------------------------------------------------------------------
-- Gate 2: sharing a public tracking link
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select public.create_ride_share_link(
      (select id from public.trips where idempotency_key = 'pv-key-0002'))$$,
  'a verified commuter can mint a share link'
);

reset role;
update public.profiles set phone_verified_at = null
 where id = '00000000-0000-0000-0000-0000000069a2';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000069a2';

select throws_ok(
  $$select public.create_ride_share_link(
      (select id from public.trips where idempotency_key = 'pv-key-0002'))$$,
  '42501',
  null,
  'SECURITY: an unverified account cannot mint the system''s only publicly '
  'readable surface'
);

-- ---------------------------------------------------------------------------
-- Gate 3: going online as a driver
-- ---------------------------------------------------------------------------
reset role;

select is(
  public.can_driver_go_online('00000000-0000-0000-0000-0000000069b1'),
  true,
  'an approved, phone-verified driver may go online'
);

update public.profiles set phone_verified_at = null
 where id = '00000000-0000-0000-0000-0000000069b1';

select is(
  public.can_driver_go_online('00000000-0000-0000-0000-0000000069b1'),
  false,
  'SECURITY: an approved driver who has NOT verified their number cannot go '
  'online, and so cannot be dispatched'
);

-- ---------------------------------------------------------------------------
-- The internal-tester bypass must not be a general hole
-- ---------------------------------------------------------------------------
-- The bypass exists because @arangcada.demo accounts have no SIM. It is only
-- defensible if an ordinary account gains nothing from it.
select is(
  public.is_verified_account('00000000-0000-0000-0000-0000000069a1'),
  false,
  'a NON-tester with no verified phone gets no benefit from the tester bypass'
);

update public.profiles set is_internal_tester = true
 where id = '00000000-0000-0000-0000-0000000069a1';

select is(
  public.is_verified_account('00000000-0000-0000-0000-0000000069a1'),
  true,
  'a flagged internal tester is exempt, so QA does not need a live SIM'
);

-- ---------------------------------------------------------------------------
-- Resend throttle
-- ---------------------------------------------------------------------------
-- Every send costs money; an unthrottled endpoint is an SMS-pumping target.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000069a2';

select lives_ok(
  $$select public.record_otp_send('+639170006902')$$,
  'the first code request is allowed'
);

select throws_ok(
  $$select public.record_otp_send('+639170006902')$$,
  '22023',
  null,
  'an immediate second request is refused -- a client loop cannot drain the '
  'prepaid SMS balance'
);

-- Rule 10: the number itself must never be stored in the log.
reset role;

select is(
  (select count(*)::integer from public.otp_send_log
    where phone_hash like '%639170006902%'),
  0,
  'PRIVACY: the throttle log stores a hash, never the phone number itself'
);

select * from finish();

rollback;
