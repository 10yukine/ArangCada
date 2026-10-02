-- 20260929030000: resend schedule (60 s, then 120 s, 4 per hour) and hook permits.
begin;
select plan(15);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008801', 'otp-a@example.test', '{"display_name":"Otp A","mobile_number":"+639170008801"}'),
('00000000-0000-0000-0000-000000008802', 'otp-b@example.test', '{"display_name":"Otp B","mobile_number":"+639170008802"}');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008801';

select ok(public.record_otp_send('+639171110001'), 'the first code is allowed');
select is((public.otp_resend_status('+639171110001')->>'sends_left')::int, 3,
  'three resends remain');
select throws_like($$select public.record_otp_send('+639171110001')$$,
  'Please wait % seconds%', 'the first resend waits 60 seconds');

reset role;
-- A second code 61 s after the first, then check the 120 s rule.
update public.otp_send_log set created_at = now() - interval '61 seconds'
 where phone_hash = public.otp_phone_hash('+639171110001');
set local role authenticated;
select ok(public.record_otp_send('+639171110001'), 'after 60 s a resend is allowed');
reset role;
-- (Inside one transaction now() never moves, so age both rows by hand.)
update public.otp_send_log
   set created_at = case when created_at < now() then now() - interval '161 seconds'
                         else now() - interval '100 seconds' end
 where phone_hash = public.otp_phone_hash('+639171110001');
set local role authenticated;
select ok((public.otp_resend_status('+639171110001')->>'wait_seconds')::int between 1 and 20,
  'later resends wait 120 seconds (20 s left after 100 s)');

reset role;
-- Four codes this hour: blocked until the first is an hour old.
insert into public.otp_send_log(user_id, phone_hash, created_at)
select '00000000-0000-0000-0000-000000008801', public.otp_phone_hash('+639171110002'), now() - (n * interval '5 minutes')
  from generate_series(1, 4) n;
set local role authenticated;
select throws_like($$select public.record_otp_send('+639171110002')$$,
  'You have used all your codes for now%', 'a fifth code in the hour is refused');
select is((public.otp_resend_status('+639171110002')->>'sends_left')::int, 0, 'no codes left this hour');

-- The hook's permit: same user and number (either format), fresh, spent once.
reset role;
set local role service_role;
select ok(public.otp_consume_permit('00000000-0000-0000-0000-000000008801', '639171110003') = false,
  'no permit without a request from the app');
reset role;
set local role authenticated;
select public.record_otp_send('+639171110003');
reset role;
set local role service_role;
select ok(public.otp_consume_permit('00000000-0000-0000-0000-000000008801', '639171110003'),
  'the hook can spend a fresh permit (Auth drops the +)');
select ok(not public.otp_consume_permit('00000000-0000-0000-0000-000000008802', '639171110003'),
  'another user cannot spend it');
reset role;
update public.otp_send_log set consumed_at = now() - interval '1 minute'
 where phone_hash = public.otp_phone_hash('+639171110003');
set local role service_role;
select ok(not public.otp_consume_permit('00000000-0000-0000-0000-000000008801', '639171110003'),
  'a spent permit cannot be reused later');

-- 20261002094000: another account's requests for a number must not use up the
-- codes of the person who owns it; codes actually delivered still count.
reset role;
insert into public.otp_send_log(user_id, phone_hash, created_at)
select '00000000-0000-0000-0000-000000008802', public.otp_phone_hash('+639171110004'), now() - (n * interval '5 minutes')
  from generate_series(1, 4) n;
set local role authenticated;
select is((public.otp_resend_status('+639171110004')->>'sends_left')::int, 4,
  'another account''s unspent requests leave the owner all four codes');
select ok(public.record_otp_send('+639171110004'), 'so the owner can still ask for one');
reset role;
update public.otp_send_log set consumed_at = created_at
 where user_id = '00000000-0000-0000-0000-000000008802'
   and phone_hash = public.otp_phone_hash('+639171110004');
set local role service_role;
select ok(not public.otp_consume_permit('00000000-0000-0000-0000-000000008801', '639171110004'),
  'a number that already received four codes this hour gets no fifth, whoever asks');
reset role;
set local role authenticated;
select is((public.otp_resend_status('+639171110004')->>'sends_left')::int, 0,
  'and delivered codes count for everyone');

select * from finish();
rollback;
