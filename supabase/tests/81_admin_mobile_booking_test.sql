begin;
select plan(7);
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-0000-0000-0000-0000000081a1','admin-mobile@example.test','{"display_name":"Mobile Admin","invited_admin":true}');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-0000000081a1';
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-0000000081a1';
select throws_ok($$select public.request_ride(14.2150,121.1650,14.2200,121.1700,'Pickup','Destination','admin-mobile-unverified')$$,
'42501','verify your mobile number before booking a ride','admin without SMS verification cannot book');
select throws_ok($$select public.abandon_unverified_registration()$$,'42501',null,'cancelling setup cannot delete an admin');
reset role;
update public.profiles set is_internal_tester=true where id='00000000-0000-0000-0000-0000000081a1';
set local role authenticated;
select throws_ok($$select public.request_ride(14.2150,121.1650,14.2200,121.1700,'Pickup','Destination','admin-mobile-test')$$,
'42501','verify your mobile number before booking a ride','admin tester also requires SMS verification');
reset role;
update auth.users set phone='+639170008101',phone_confirmed_at=now() where id='00000000-0000-0000-0000-0000000081a1';
set local role authenticated;
select lives_ok($$select public.request_ride(14.2150,121.1650,14.2200,121.1700,'Pickup','Destination','admin-mobile-verified')$$,'phone-verified admin can book as rider');
select is((select role::text from public.profiles where id=auth.uid()),'admin','booking preserves website admin role');
select ok(public.is_admin(auth.uid()),'website admin access remains available');
reset role;
update public.profiles set status='suspended' where id='00000000-0000-0000-0000-0000000081a1';
set local role authenticated;
select throws_ok($$select public.request_ride(14.2150,121.1650,14.2200,121.1700,'Pickup','Destination','admin-mobile-suspended')$$,
'42501',null,'suspended admin cannot book');
select * from finish();
rollback;
