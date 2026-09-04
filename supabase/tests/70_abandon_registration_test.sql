-- pgTAP: abandoning an unverified registration, and the throttle it endangers.
--
-- WHY THIS FILE EXISTS
--
-- abandon_unverified_registration() is a security-definer function that DELETES
-- FROM auth.users. There is no more dangerous shape of function in this schema,
-- and exactly one thing stops it being a "delete any account" endpoint: the
-- phone_confirmed_at IS NULL guard. Every assertion about that guard below is
-- load-bearing.
--
-- The second half is subtler and matters more. otp_send_log used to cascade
-- from profiles, which cascades from auth.users -- so making accounts deletable
-- silently made the OTP throttle resettable: register, request a code, abandon,
-- register again, request another, forever. The FK is now ON DELETE SET NULL
-- and the limits are keyed on hashes rather than on the account. A future
-- migration "tidying up" that nullable column would reopen the bypass without
-- breaking anything visible, so it is asserted here directly.

begin;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures: an unverified commuter, a verified one, an internal tester, and an
-- administrator. Only the first should ever be deletable.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, phone_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000070a1', 'ab-unverified@example.test', null,
   '{"display_name":"AB Unverified","mobile_number":"+639170007001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000070a2', 'ab-verified@example.test', now(),
   '{"display_name":"AB Verified","mobile_number":"+639170007002"}'::jsonb),
  ('00000000-0000-0000-0000-0000000070a3', 'ab-tester@example.test', null,
   '{"display_name":"AB Tester","mobile_number":"+639170007003"}'::jsonb),
  ('00000000-0000-0000-0000-0000000070a4', 'ab-admin@example.test', null,
   '{"display_name":"AB Admin","mobile_number":"+639170007004"}'::jsonb);

-- handle_new_user() has already created these rows from the metadata above, so
-- this is an upsert that sets only what the trigger cannot know: the role and
-- the tester flag.
insert into public.profiles (id, role, display_name, phone, email, status, is_internal_tester) values
  ('00000000-0000-0000-0000-0000000070a1', 'commuter', 'AB Unverified',
   '+639170007001', 'ab-unverified@example.test', 'active', false),
  ('00000000-0000-0000-0000-0000000070a2', 'commuter', 'AB Verified',
   '+639170007002', 'ab-verified@example.test',   'active', false),
  ('00000000-0000-0000-0000-0000000070a3', 'commuter', 'AB Tester',
   '+639170007003', 'ab-tester@example.test',     'active', true),
  ('00000000-0000-0000-0000-0000000070a4', 'admin',    'AB Admin',
   '+639170007004', 'ab-admin@example.test',      'active', false)
on conflict (id) do update
  set role = excluded.role,
      is_internal_tester = excluded.is_internal_tester;

-- ---------------------------------------------------------------------------
-- Grants: this must never be reachable without a session
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('anon', 'public.abandon_unverified_registration()', 'execute'),
  'anon cannot delete accounts'
);

select ok(
  has_function_privilege('authenticated', 'public.abandon_unverified_registration()', 'execute'),
  'a signed-in user can abandon their own registration'
);

-- The sweep takes an interval argument and could otherwise be called with a
-- zero age, which would delete every unverified account in the system --
-- including ones registered seconds ago.
select ok(
  not has_function_privilege('authenticated', 'public.sweep_abandoned_registrations(interval)', 'execute'),
  'an ordinary user cannot run the sweep'
);

select ok(
  not has_function_privilege('anon', 'public.sweep_abandoned_registrations(interval)', 'execute'),
  'anon cannot run the sweep'
);

-- ---------------------------------------------------------------------------
-- The guard, in every direction
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000070a2';

select throws_ok(
  $$select public.abandon_unverified_registration()$$,
  '42501',
  null,
  'a verified account cannot be deleted through this function'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000070a3';

-- An internal tester's phone_confirmed_at is null permanently by design, so
-- the primary guard does not protect them. Without the explicit exemption a
-- tester tapping "Go Back" would delete the fixture every QA run depends on.
select throws_ok(
  $$select public.abandon_unverified_registration()$$,
  '42501',
  null,
  'an internal tester cannot abandon itself'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000070a4';

select throws_ok(
  $$select public.abandon_unverified_registration()$$,
  '42501',
  null,
  'an administrator cannot abandon itself'
);

-- ---------------------------------------------------------------------------
-- The throttle must outlive the account
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000070a1';

select lives_ok(
  $$select public.record_otp_send('+639170007001')$$,
  'the first code request for a number is allowed'
);

select throws_ok(
  $$select public.record_otp_send('+639170007001')$$,
  '22023',
  null,
  'a second request for the same number inside 60s is refused'
);

select is(
  (select count(*)::int from public.otp_send_log
    where user_id = '00000000-0000-0000-0000-0000000070a1'),
  1,
  'the send was logged against the account'
);

-- ---------------------------------------------------------------------------
-- The delete itself
-- ---------------------------------------------------------------------------
select lives_ok(
  $$select public.abandon_unverified_registration()$$,
  'an unverified account can abandon itself'
);

reset role;

select is(
  (select count(*)::int from auth.users
    where id = '00000000-0000-0000-0000-0000000070a1'),
  0,
  'the auth user is gone, so the email is immediately reusable'
);

-- THE REGRESSION THAT MATTERS. If otp_send_log still cascaded, this row would
-- have vanished with the account and the next registration would start with a
-- clean throttle -- register, request, abandon, repeat, indefinitely.
select is(
  (select count(*)::int from public.otp_send_log
    where phone_hash = encode(sha256('+639170007001'::bytea), 'hex')),
  1,
  'the OTP send log survives the account it belonged to'
);

-- And it survives orphaned rather than half-deleted, so the counting queries
-- still see it.
select is(
  (select user_id from public.otp_send_log
    where phone_hash = encode(sha256('+639170007001'::bytea), 'hex')),
  null,
  'the orphaned log row keeps its hashes and drops only the user reference'
);

-- ---------------------------------------------------------------------------
-- Review finding 1: the IP cap must not trust a client-supplied address
-- ---------------------------------------------------------------------------
-- x-forwarded-for's FIRST entry is whatever the caller claimed. If the throttle
-- reads that, an attacker sends a different value each request and the per-IP
-- cap -- the only limit that binds someone walking through many numbers --
-- stops existing. Here the client claims 9.9.9.9 while the trusted Cloudflare
-- header says 10.0.0.1; the log must record the trusted one.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000070a2';
set local request.headers = '{"x-forwarded-for":"9.9.9.9, 10.0.0.1","cf-connecting-ip":"10.0.0.1"}';

select lives_ok(
  $$select public.record_otp_send('+639170007099')$$,
  'a send is recorded when headers are present'
);

select is(
  (select ip_hash from public.otp_send_log
    where phone_hash = encode(sha256('+639170007099'::bytea), 'hex')),
  encode(sha256('10.0.0.1'::bytea), 'hex'),
  'the throttle hashes the proxy-set address, not the one the client claimed'
);

reset role;

-- ---------------------------------------------------------------------------
-- Review finding 2: the sweep must not delete an onboarded driver
-- ---------------------------------------------------------------------------
-- A driver onboarded by an administrator who never completed SMS verification
-- has no confirmed phone and, when newly approved, no trips -- matching every
-- other condition the sweep tests. Deleting them would cascade away their
-- verification documents.
insert into auth.users (id, email, phone_confirmed_at, created_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000070a5', 'ab-driver@example.test', null,
   now() - interval '30 days',
   '{"display_name":"AB Driver","mobile_number":"+639170007005"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000070a5', 'driver', 'AB Driver',
   '+639170007005', 'ab-driver@example.test', 'active')
on conflict (id) do update set role = excluded.role;

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status) values
  ('00000000-0000-0000-0000-0000000070a5',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   '00000000-0000-0000-0000-0000000070a4', 'approved')
on conflict (id) do nothing;

select lives_ok(
  $$select public.sweep_abandoned_registrations(interval '1 hour')$$,
  'the sweep runs'
);

select is(
  (select count(*)::int from auth.users
    where id = '00000000-0000-0000-0000-0000000070a5'),
  1,
  'an onboarded driver survives the sweep despite never verifying a number'
);

select * from finish();

rollback;
