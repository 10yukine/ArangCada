-- 20261002150000: the oldest accepted mobile build and the service switches.
begin;
select plan(11);

select is(public.get_mobile_settings(),
  '{"min_mobile_build": 0, "routing": "google", "search": "google", "pickup_free_m": 0, "pickup_charge_max_m": 0}'::jsonb,
  'the defaults accept every build and use Google first');

set local role anon;
select is(public.get_mobile_settings() ->> 'min_mobile_build', '0', 'a signed-out app can ask');
select throws_ok($$ update public.mobile_settings set min_mobile_build = 9999 $$,
  '42501', null, 'a signed-out caller cannot change it');
reset role;

-- An administrator must not be able to lock every user out through the API.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000094c1', 'ms-admin@example.test',
     '{"display_name":"Ms Admin","mobile_number":"+639170009401"}'::jsonb);
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000094c1';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000094c1';
select is(public.get_mobile_settings() ->> 'routing', 'google', 'a signed-in app can ask');
select throws_ok($$ update public.mobile_settings set routing = 'ors_only' $$,
  '42501', null, 'an administrator cannot change it through the API');
select throws_ok($$ select * from public.mobile_settings $$,
  '42501', null, 'the table itself is not readable through the API');
reset role;

update public.mobile_settings set min_mobile_build = 4035, routing = 'ors_only', search = 'maptiler';
set local role anon;
select is(public.get_mobile_settings(),
  '{"min_mobile_build": 4035, "routing": "ors_only", "search": "maptiler", "pickup_free_m": 0, "pickup_charge_max_m": 0}'::jsonb,
  'the app sees what the owner set');
reset role;

select throws_ok($$ update public.mobile_settings set min_mobile_build = -1 $$,
  '23514', null, 'a negative minimum is refused');
select throws_ok($$ update public.mobile_settings set routing = 'none' $$,
  '23514', null, 'an unknown routing choice is refused');
select throws_ok($$ update public.mobile_settings set search = 'bing' $$,
  '23514', null, 'an unknown search choice is refused');
select throws_ok($$ insert into public.mobile_settings (id) values (true) $$,
  '23505', null, 'there is only ever one row');

select * from finish();
rollback;
