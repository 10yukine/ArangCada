-- 20261006090000: the switch from emailed codes to text messages asks every
-- earlier-verified account to confirm its number again, and deletes none.
begin;
select plan(27);

insert into auth.users (id, email, created_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000101c1', 'pr-lgu@example.test', now() - interval '3 days',
     '{"display_name":"Pr Lgu","mobile_number":"+639170010100"}'::jsonb),
  -- Verified while codes were emailed; has never taken a trip.
  ('00000000-0000-0000-0000-0000000101a1', 'pr-rider@example.test', now() - interval '3 days',
     '{"display_name":"Pr Rider","mobile_number":"+639170010101"}'::jsonb),
  -- Started a sign-up days ago and never entered a code.
  ('00000000-0000-0000-0000-0000000101a2', 'pr-stale@example.test', now() - interval '3 days',
     '{"display_name":"Pr Stale","mobile_number":"+639170010102"}'::jsonb),
  -- In the middle of signing up right now.
  ('00000000-0000-0000-0000-0000000101a3', 'pr-new@example.test', now(),
     '{"display_name":"Pr New","mobile_number":"+639170010103"}'::jsonb),
  -- Verified, with a trip in progress.
  ('00000000-0000-0000-0000-0000000101a4', 'pr-riding@example.test', now() - interval '3 days',
     '{"display_name":"Pr Riding","mobile_number":"+639170010104"}'::jsonb);

update public.profiles set role = 'admin'
 where id = '00000000-0000-0000-0000-0000000101c1';
update auth.users set phone = '639170010101', phone_confirmed_at = now() - interval '2 days'
 where id = '00000000-0000-0000-0000-0000000101a1';
update auth.users set phone = '639170010104', phone_confirmed_at = now() - interval '2 days'
 where id = '00000000-0000-0000-0000-0000000101a4';

create temporary table pr_zone as
  select id from public.toda_zones where is_active order by code limit 1;
grant select on pr_zone to authenticated;

-- Nothing has changed until the switch is run.
select is(
  (select sms_live_since from public.phone_verification_settings), null,
  'codes are not by text until the switch is run');
select ok(
  not has_function_privilege('authenticated', 'public.begin_phone_reverification()', 'execute')
  and not has_function_privilege('anon', 'public.begin_phone_reverification()', 'execute'),
  'no app user can run the switch');
select ok(
  not has_column_privilege('authenticated', 'public.profiles', 'phone_reverify_since', 'update'),
  'a signed-in user cannot mark or unmark their own account');
select ok(
  not has_table_privilege('authenticated', 'public.phone_verification_settings', 'select')
  and not has_table_privilege('anon', 'public.phone_verification_settings', 'select'),
  'the settings row is not readable through the API');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000101c1';
select is(
  (select count(*)::int from public.admin_preview_driver_candidate('pr-rider@example.test', null)),
  1, 'while codes are emailed, a verified account can be matched by its email');
reset role;

-- The switch waits for open trips.
insert into public.trips (id, rider_id, status, pickup, dropoff) values
  ('00000000-0000-0000-0000-000000010111', '00000000-0000-0000-0000-0000000101a4', 'requested',
   st_setsrid(st_makepoint(121.16, 14.2), 4326), st_setsrid(st_makepoint(121.17, 14.21), 4326));
select throws_ok(
  $$select public.begin_phone_reverification()$$,
  '55000', 'a trip is still open; run this when no trip is in progress',
  'the switch is refused while a trip is open');
select is(
  (select sms_live_since from public.phone_verification_settings), null,
  'and a refused switch records nothing');
delete from public.trips where id = '00000000-0000-0000-0000-000000010111';

-- The switch.
create temporary table pr_before as
  select count(*)::int as verified from public.profiles where phone_verified_at is not null;
select is(
  public.begin_phone_reverification(), (select verified from pr_before),
  'every account verified before the switch is sent to confirm again');
select isnt(
  (select sms_live_since from public.phone_verification_settings), null,
  'the moment codes went by text is recorded');
select is(
  (select count(*)::int from public.profiles where phone_verified_at is not null), 0,
  'no earlier confirmation is left standing');
select ok(
  (select phone_verified_at is null and phone_reverify_since is not null and phone is not null
     from public.profiles where id = '00000000-0000-0000-0000-0000000101a1'),
  'the account is unverified, marked, and still knows its number');
select ok(
  (select phone is null and phone_confirmed_at is null
     from auth.users where id = '00000000-0000-0000-0000-0000000101a1'),
  'Auth holds no number, so the app can ask for a new code');
select is(
  (select phone_reverify_since from public.profiles
    where id = '00000000-0000-0000-0000-0000000101a2'),
  null, 'a sign-up that never verified is not marked');

-- "Go back" on the verify screen must not delete an established account.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000101a1';
select throws_ok(
  $$select public.abandon_unverified_registration()$$,
  '42501', 'this account is confirming its number again and cannot be abandoned',
  'an account confirming again cannot be abandoned');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000101a3';
select lives_ok(
  $$select public.abandon_unverified_registration()$$,
  'a sign-up in progress can still be abandoned');
reset role;
select is(
  (select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000101a3'),
  0, 'and is removed');

-- The hourly sweep.
select lives_ok(
  $$select public.sweep_abandoned_registrations('0 seconds'::interval)$$,
  'the sweep runs');
select is(
  (select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000101a1'),
  1, 'the sweep leaves an account that is confirming again');
select is(
  (select count(*)::int from auth.users where id = '00000000-0000-0000-0000-0000000101a2'),
  0, 'and still removes a sign-up that never verified');

-- Confirming again by text.
update auth.users set phone = '639170010101', phone_confirmed_at = now() + interval '1 minute'
 where id = '00000000-0000-0000-0000-0000000101a1';
select isnt(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000101a1'),
  null, 'entering the texted code verifies the account again');
select is(
  public.begin_phone_reverification(), 0,
  'running the switch again asks nobody twice');
select isnt(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000101a1'),
  null, 'and leaves a number confirmed by text alone');

-- After the switch a verified number says nothing about the mailbox.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000101c1';
select is(
  (select count(*)::int from public.admin_preview_driver_candidate('pr-rider@example.test', null)),
  0, 'an account that has not confirmed its email is not matched by email');
select throws_ok(
  $$select public.admin_promote_commuter_to_driver('email', 'pr-rider@example.test', null,
      'pr-rider@example.test', (select id from pr_zone), null, null)$$,
  'P0002', null, 'and cannot be promoted by email');
select throws_ok(
  $$select public.admin_create_driver_invite('pr-rider@example.test', (select id from pr_zone), null)$$,
  '23505',
  'this email belongs to an account that has not confirmed it -- ask the driver to confirm the email from the Profile screen in the app, or enrol them by mobile number',
  'the invite refusal says what to do');
select is(
  (select count(*)::int from public.admin_preview_driver_candidate(null, '+639170010101')),
  1, 'the same account can be matched by its texted number');
reset role;

update public.profiles set email_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000101a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000101c1';
select is(
  (select count(*)::int from public.admin_preview_driver_candidate('pr-rider@example.test', null)),
  1, 'once the email link is opened, the email matches again');
reset role;

select * from finish();
rollback;
