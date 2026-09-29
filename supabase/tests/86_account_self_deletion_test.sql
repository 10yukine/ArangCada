-- delete_account (20260929010000): personal data goes, retained records stay de-identified.
begin;
select plan(16);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008601', 'del-rider@example.test', '{"display_name":"Del Rider","mobile_number":"+639170008601"}'),
('00000000-0000-0000-0000-000000008602', 'del-driver@example.test', '{"display_name":"Del Driver","mobile_number":"+639170008602"}'),
('00000000-0000-0000-0000-000000008603', 'del-admin@example.test', '{"display_name":"Del Admin","mobile_number":"+639170008603"}'),
('00000000-0000-0000-0000-000000008604', 'del-busy@example.test', '{"display_name":"Del Busy","mobile_number":"+639170008604"}');
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-000000008603';
update public.profiles set role = 'driver' where id = '00000000-0000-0000-0000-000000008602';

create temporary table del_zone as select id, name from public.toda_zones where is_active order by code limit 1;
insert into public.driver_profiles(id, toda_zone_id, promoted_by)
values ('00000000-0000-0000-0000-000000008602', (select id from del_zone), '00000000-0000-0000-0000-000000008603');
insert into public.driver_documents(driver_id, document_type, storage_path)
values ('00000000-0000-0000-0000-000000008602', (enum_range(null::public.document_type))[1],
        '00000000-0000-0000-0000-000000008602/licence.jpg');

insert into public.trips(id, rider_id, driver_id, status, rider_display_name, driver_display_name, pickup, dropoff) values
('00000000-0000-0000-0000-000000008611', '00000000-0000-0000-0000-000000008601', '00000000-0000-0000-0000-000000008602',
 'completed', 'Del Rider', 'Del Driver',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326)),
('00000000-0000-0000-0000-000000008612', '00000000-0000-0000-0000-000000008604', null, 'searching_driver', 'Del Busy', null,
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));

insert into public.trip_messages(id, trip_id, sender_id, body, voice_path, voice_duration_ms) values
('00000000-0000-0000-0000-000000008621', '00000000-0000-0000-0000-000000008611', '00000000-0000-0000-0000-000000008601', 'on my way',
 '00000000-0000-0000-0000-000000008611/00000000-0000-0000-0000-000000008601/00000000-0000-0000-0000-000000008621.m4a', 1200);
insert into public.trip_ratings(trip_id, toda_zone_id, toda_name, rater_id, rater_role, rater_display_name, ratee_id, ratee_display_name, stars)
values ('00000000-0000-0000-0000-000000008611', (select id from del_zone), 'Z', '00000000-0000-0000-0000-000000008601',
        'commuter', 'Del Rider', '00000000-0000-0000-0000-000000008602', 'Del Driver', 5);
insert into public.complaints(trip_id, toda_zone_id, complainant_id, complainant_role, complainant_display_name,
                              respondent_id, respondent_display_name, toda_name, category, description, idempotency_key)
values ('00000000-0000-0000-0000-000000008611', (select id from del_zone), '00000000-0000-0000-0000-000000008601', 'commuter',
        'Del Rider', '00000000-0000-0000-0000-000000008602', 'Del Driver', 'Z', 'other', 'late', 'del-c1');
insert into public.sos_reports(trip_id, toda_zone_id, reporter_id, reporter_role, reporter_display_name, driver_display_name,
                               toda_name, reason, idempotency_key)
values ('00000000-0000-0000-0000-000000008611', (select id from del_zone), '00000000-0000-0000-0000-000000008601', 'commuter',
        'Del Rider', 'Del Driver', 'Z', 'test', 'del-s1');
insert into public.fare_class_claims(profile_id, claimant_display_name, requested_class, id_photo_path)
values ('00000000-0000-0000-0000-000000008601', 'Del Rider', 'student', '00000000-0000-0000-0000-000000008601/id.jpg');
insert into public.ride_share_links(trip_id, created_by)
values ('00000000-0000-0000-0000-000000008611', '00000000-0000-0000-0000-000000008601');

-- Only the edge function (service_role) may call it.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008601';
select throws_ok($$select public.delete_account('00000000-0000-0000-0000-000000008601')$$,
  '42501', null, 'a signed-in user cannot call delete_account directly');
reset role;
set local role service_role;

select throws_ok($$select public.delete_account('00000000-0000-0000-0000-000000008604')$$,
  '55000', null, 'nobody can delete their account mid-ride');
select throws_ok($$select public.delete_account('00000000-0000-0000-0000-000000008603')$$,
  '55000', null, 'administrators are removed from the admin console instead');

create temporary table del_files as
  select public.delete_account('00000000-0000-0000-0000-000000008601') as files;
select is((select files->'trip-voice-notes'->>0 from del_files),
  '00000000-0000-0000-0000-000000008611/00000000-0000-0000-0000-000000008601/00000000-0000-0000-0000-000000008621.m4a',
  'the voice notes to remove from Storage are returned');
select is((select files->'discount-eligibility-ids'->>0 from del_files),
  '00000000-0000-0000-0000-000000008601/id.jpg', 'the discount ID photo to remove is returned');

create temporary table driver_files as
  select public.delete_account('00000000-0000-0000-0000-000000008602') as files;
select is((select files->'driver-documents'->>0 from driver_files),
  '00000000-0000-0000-0000-000000008602/licence.jpg', 'a driver''s documents to remove are returned');

reset role;
select is((select count(*)::int from auth.users where id in
  ('00000000-0000-0000-0000-000000008601', '00000000-0000-0000-0000-000000008602')), 0, 'both accounts are gone');
select is((select count(*)::int from public.driver_profiles where id = '00000000-0000-0000-0000-000000008602'),
  0, 'the driver record is gone');
select is((select count(*)::int from public.trip_messages where trip_id = '00000000-0000-0000-0000-000000008611'),
  0, 'their chat messages are gone');
select is((select count(*)::int from public.fare_class_claims where claimant_display_name = 'Del Rider')
          + (select count(*)::int from public.ride_share_links where trip_id = '00000000-0000-0000-0000-000000008611'),
  0, 'claims and share links are gone');
select is((select row(rider_id, driver_id, rider_display_name, driver_display_name)::text from public.trips
            where id = '00000000-0000-0000-0000-000000008611'),
  '(,,"Deleted account","Deleted account")', 'the trip is kept without identity');
select is((select row(complainant_id, respondent_id, complainant_display_name, respondent_display_name)::text
             from public.complaints where idempotency_key = 'del-c1'),
  '(,,"Deleted account","Deleted account")', 'the complaint is kept without identity');
select is((select row(rater_id, ratee_id, rater_display_name, ratee_display_name)::text
             from public.trip_ratings where trip_id = '00000000-0000-0000-0000-000000008611'),
  '(,,"Deleted account","Deleted account")', 'the rating is kept without identity');
select is((select row(reporter_id, reporter_display_name, driver_display_name)::text
             from public.sos_reports where idempotency_key = 'del-s1'),
  '(,"Deleted account","Deleted account")', 'the SOS report is kept without identity');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-000000008604'),
  1, 'the blocked account is untouched');
select is((select count(*)::int from auth.users where id = '00000000-0000-0000-0000-000000008603'),
  1, 'the administrator is untouched');

select * from finish();
rollback;
