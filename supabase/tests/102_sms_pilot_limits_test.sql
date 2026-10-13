-- 20261013090000: a text message is held to the pilot's limits: how many
-- different numbers, how many numbers per account, how many texts in 30 days,
-- and the last day. Emailed codes are not counted.
begin;
select plan(17);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000010201', 'sms-a@example.test', '{"display_name":"Sms A","mobile_number":"+639170010201"}'),
('00000000-0000-0000-0000-000000010202', 'sms-b@example.test', '{"display_name":"Sms B","mobile_number":"+639170010202"}');

select results_eq(
  $$select max_sms_recipients, max_numbers_per_account, max_sms_per_month, sms_until
      from public.phone_verification_settings$$,
  $$values (125, 3, 1000, date '2027-07-31')$$,
  'the limits start at the pilot''s numbers');

-- Account A asks for a code; the hook spends the permit as a text.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';
select public.record_otp_send('+639171020001');
reset role;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020002'),
  'no_permit', 'a number the app never asked for gets no text');
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010202', '639171020001'),
  'no_permit', 'another account cannot spend the permit');
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020001'),
  'ok', 'a requested code may go out as a text');
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020001'),
  'ok', 'Auth sending the same text again is not refused');
reset role;
select is((select count(*) from public.otp_send_log where sms_sent_at is not null),
  1::bigint, 'and is counted once');

-- An emailed code is spent through the old function and is not counted.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010202';
select public.record_otp_send('+639171020009');
reset role;
set local role service_role;
select ok(public.otp_consume_permit('00000000-0000-0000-0000-000000010202', '639171020009'),
  'the emailed-code permit still works');
reset role;
select is((select count(*) from public.otp_send_log where sms_sent_at is not null),
  1::bigint, 'an emailed code is not counted as a text');

-- The recipient list is full: no new number, but a number already on it.
update public.phone_verification_settings set max_sms_recipients = 1;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';
select public.record_otp_send('+639171020003');
reset role;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003'),
  'recipient_cap', 'a new number is refused once the list is full');
reset role;
-- (now() does not move inside a transaction, so age the first request.)
update public.otp_send_log set created_at = now() - interval '5 minutes'
 where phone_hash = public.otp_phone_hash('+639171020001');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010201';
select public.record_otp_send('+639171020001');
reset role;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020001'),
  'ok', 'a number already on the list can still get a code');
reset role;
update public.phone_verification_settings set max_sms_recipients = 125;

-- One account, too many different numbers.
update public.phone_verification_settings set max_numbers_per_account = 1;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003'),
  'account_cap', 'an account that already texted one number may not text a second');
reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000010202';
select public.record_otp_send('+639171020004');
reset role;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010202', '639171020004'),
  'ok', 'another account is not held back by it');
reset role;
update public.phone_verification_settings set max_numbers_per_account = 3;

-- The month's texts are used up (three so far).
update public.phone_verification_settings set max_sms_per_month = 3;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003'),
  'month_cap', 'no text once the 30-day count is reached');
reset role;
update public.phone_verification_settings set max_sms_per_month = 1000;

-- After the last day.
update public.phone_verification_settings
   set sms_until = (now() at time zone 'Asia/Manila')::date - 1;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003'),
  'ended', 'no text after the last day');
reset role;
update public.phone_verification_settings
   set sms_until = (now() at time zone 'Asia/Manila')::date;
set local role service_role;
select is(public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003'),
  'ok', 'the last day itself still sends');
reset role;

-- Only the hook may ask, and only the owner may change the limits.
set local role authenticated;
select throws_ok(
  $$select public.sms_send_permit('00000000-0000-0000-0000-000000010201', '639171020003')$$,
  '42501', null, 'an app user cannot call it');
select throws_ok($$ update public.phone_verification_settings set max_sms_recipients = 9999 $$,
  '42501', null, 'no account can change the limits through the API');
reset role;

select * from finish();
rollback;
