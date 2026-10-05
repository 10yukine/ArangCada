-- 20261005130000: an email is confirmed only by redeeming a link the server
-- made, and a signed-in user can neither make nor redeem one.
begin;
select plan(18);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000100a1', 'ec-rider@example.test',
   '{"display_name":"EC Rider","mobile_number":"+639170010001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000100a2', 'ec-unverified@example.test',
   '{"display_name":"EC Unverified","mobile_number":"+639170010002"}'::jsonb);
update public.profiles set phone_verified_at = now()
 where id = '00000000-0000-0000-0000-0000000100a1';

create temporary table ec_hash (name text primary key, hash text not null);
insert into ec_hash values
  ('first',  encode(sha256('first-link'::bytea), 'hex')),
  ('second', encode(sha256('second-link'::bytea), 'hex')),
  ('third',  encode(sha256('third-link'::bytea), 'hex'));

select is(
  (select email_confirmed_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000100a1'),
  null, 'a new account starts unconfirmed');

-- Making a link.
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a2',
      (select hash from ec_hash where name = 'first'))$$,
  '22023', 'Verify your mobile number first.',
  'no link before the mobile number is verified');
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a1', 'not-a-hash')$$,
  '22023', null, 'the link must be given as a SHA-256 hash');
select is(
  public.create_email_confirmation(
    '00000000-0000-0000-0000-0000000100a1',
    (select hash from ec_hash where name = 'first')),
  'ec-rider@example.test', 'a link is recorded and the address returned');
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a1',
      (select hash from ec_hash where name = 'second'))$$,
  '22023', 'Please wait a minute before asking for another link.',
  'a second link within a minute is refused');

-- Five a day.
update public.email_confirmations set created_at = now() - interval '2 hours';
insert into public.email_confirmations (token_hash, user_id, email, created_at, expires_at)
select encode(sha256(('filler-' || n)::bytea), 'hex'),
       '00000000-0000-0000-0000-0000000100a1', 'ec-rider@example.test',
       now() - interval '3 hours', now() + interval '21 hours'
  from generate_series(1, 4) n;
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a1',
      (select hash from ec_hash where name = 'second'))$$,
  '22023', 'You have asked for the most links allowed today. Try again tomorrow.',
  'a sixth link in a day is refused');
delete from public.email_confirmations
 where token_hash <> (select hash from ec_hash where name = 'first');

-- Redeeming.
select is(public.confirm_email(encode(sha256('never-issued'::bytea), 'hex')), false,
  'an unknown link confirms nothing');
select is(public.confirm_email((select hash from ec_hash where name = 'first')), true,
  'the link confirms the email');
select isnt(
  (select email_confirmed_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000100a1'),
  null, 'and the account is marked confirmed');
select is(public.confirm_email((select hash from ec_hash where name = 'first')), false,
  'a link works once');
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a1',
      (select hash from ec_hash where name = 'second'))$$,
  '22023', 'This email is already confirmed.',
  'a confirmed email needs no new link');

-- Changing the email takes the confirmation away, and an old link does not
-- confirm the new address.
update public.email_confirmations set created_at = now() - interval '2 hours';
update auth.users set email = 'ec-rider-new@example.test'
 where id = '00000000-0000-0000-0000-0000000100a1';
select is(
  (select email_confirmed_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000100a1'),
  null, 'a changed email is unconfirmed again');
insert into public.email_confirmations (token_hash, user_id, email, expires_at)
values ((select hash from ec_hash where name = 'second'),
        '00000000-0000-0000-0000-0000000100a1', 'ec-rider@example.test',
        now() + interval '1 hour');
select is(public.confirm_email((select hash from ec_hash where name = 'second')), false,
  'a link sent to the old address does not confirm the new one');

-- An expired link.
insert into public.email_confirmations (token_hash, user_id, email, created_at, expires_at)
values ((select hash from ec_hash where name = 'third'),
        '00000000-0000-0000-0000-0000000100a1', 'ec-rider-new@example.test',
        now() - interval '25 hours', now() - interval '1 hour');
select is(public.confirm_email((select hash from ec_hash where name = 'third')), false,
  'an expired link confirms nothing');

-- A signed-in user can do none of this directly.
grant select on ec_hash to authenticated;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select throws_ok(
  $$select public.create_email_confirmation(
      '00000000-0000-0000-0000-0000000100a1',
      (select hash from ec_hash where name = 'first'))$$,
  '42501', null, 'a signed-in user cannot make a link');
select throws_ok(
  $$select public.confirm_email((select hash from ec_hash where name = 'first'))$$,
  '42501', null, 'nor redeem one');
select throws_ok(
  $$update public.profiles set email_confirmed_at = now()
     where id = '00000000-0000-0000-0000-0000000100a1'$$,
  '42501', null, 'nor mark the email confirmed');
select throws_ok(
  $$select * from public.email_confirmations$$,
  '42501', null, 'nor read the links');
reset role;

select * from finish();
rollback;
