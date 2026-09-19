begin;
select no_plan();
insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000009901', 'phone-rider@example.test', '{"display_name":"Phone Rider","mobile_number":"+639170009901"}'),
('00000000-0000-0000-0000-000000009902', 'phone-driver@example.test', '{"display_name":"Phone Driver","mobile_number":"+639170009902"}'),
('00000000-0000-0000-0000-000000009903', 'phone-outsider@example.test', '{"display_name":"Phone Outsider","mobile_number":"+639170009903"}');
insert into public.trips(id, rider_id, driver_id, status, pickup, dropoff) values
('00000000-0000-0000-0000-000000009911',
 '00000000-0000-0000-0000-000000009901', '00000000-0000-0000-0000-000000009902',
 'accepted', st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009901';
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), '+639170009902', 'rider gets driver phone');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009902';
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), '+639170009901', 'driver gets rider phone');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009903';
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), null::text, 'outsider cannot read contact');
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009999'), null::text, 'missing trip has identical response');
set local request.jwt.claim.sub = '';
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), null::text, 'missing identity cannot read contact');
reset role;
select ok(not has_function_privilege('anon','public.trip_counterpart_phone(uuid)','EXECUTE'), 'anonymous execution denied');
update public.trips set status = 'completed', completed_at = now() where id = '00000000-0000-0000-0000-000000009911';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000009901';
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), null::text, 'ended trip cannot expose contact');
reset role;
update public.trips set status = 'driver_assigned' where id = '00000000-0000-0000-0000-000000009911';
set local role authenticated;
select is(public.trip_counterpart_phone('00000000-0000-0000-0000-000000009911'), null::text, 'unaccepted trip cannot expose contact');
select * from finish();
rollback;
