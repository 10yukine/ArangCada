-- 20261002130000: an account that never verified cannot be made a driver by
-- its email, and the invite refusal says why.
begin;
select plan(8);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000093c1', 'de-lgu@example.test',
     '{"display_name":"De Lgu","mobile_number":"+639170009301"}'::jsonb),
  ('00000000-0000-0000-0000-0000000093a1', 'de-squatted@example.test',
     '{"display_name":"Juan Dela Cruz","mobile_number":"+639170009302"}'::jsonb),
  ('00000000-0000-0000-0000-0000000093a2', 'de-verified@example.test',
     '{"display_name":"Maria Santos","mobile_number":"+639170009303"}'::jsonb);

update public.profiles set role = 'admin', phone_verified_at = now()
 where id = '00000000-0000-0000-0000-0000000093c1';
update public.profiles set phone_verified_at = now()
 where id = '00000000-0000-0000-0000-0000000093a2';

create temporary table de_zone as
  select id from public.toda_zones where is_active order by code limit 1;
grant select on de_zone to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000093c1';

-- The account that registered someone else's email and never entered a code.
select is(
  (select count(*)::int from public.admin_preview_driver_candidate('de-squatted@example.test', null)),
  0, 'an unverified account is not offered for promotion');
select throws_ok(
  $$select public.admin_promote_commuter_to_driver('email', 'de-squatted@example.test', null,
      'de-squatted@example.test', (select id from de_zone), null, null)$$,
  'P0002', null, 'an unverified account cannot be promoted by its email');
select throws_ok(
  $$select public.admin_create_driver_invite('de-squatted@example.test', (select id from de_zone), null)$$,
  '23505',
  'this email has a sign-up that was never verified -- it is removed about two hours after it was started; send the invite after that',
  'the invite refusal says the sign-up is unfinished');

reset role;
select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000093a1'),
  'commuter', 'the unverified account is still a commuter');
select is(
  (select count(*)::int from public.driver_profiles where id = '00000000-0000-0000-0000-0000000093a1'),
  0, 'and has no driver record');

-- A verified account is enrolled as before.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000093c1';
select is(
  (select count(*)::int from public.admin_preview_driver_candidate('de-verified@example.test', null)),
  1, 'a verified account is offered for promotion');
select throws_ok(
  $$select public.admin_create_driver_invite('de-verified@example.test', (select id from de_zone), null)$$,
  '23505', 'this email already belongs to an account -- use the promote flow instead',
  'a verified account is still sent to the promote flow');
select lives_ok(
  $$select public.admin_promote_commuter_to_driver('email', 'de-verified@example.test', null,
      'de-verified@example.test', (select id from de_zone), null, null)$$,
  'a verified account can be promoted by its email');

select * from finish();
rollback;
