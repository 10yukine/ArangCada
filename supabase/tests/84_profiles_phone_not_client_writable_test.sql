begin;
select plan(3);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008401', 'phone-owner@example.test', '{"display_name":"Phone Owner","mobile_number":"+639170008401"}');

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008401';

select throws_ok($$update public.profiles set phone = '+639170008499'
                   where id = '00000000-0000-0000-0000-000000008401'$$,
  '42501', null, 'a user cannot change their phone without OTP');
select lives_ok($$update public.profiles set display_name = 'Renamed Owner'
                  where id = '00000000-0000-0000-0000-000000008401'$$,
  'the display name stays editable');

reset role;
select is((select phone from public.profiles where id = '00000000-0000-0000-0000-000000008401'),
  '+639170008401', 'the verified number is unchanged');

select * from finish();
rollback;
