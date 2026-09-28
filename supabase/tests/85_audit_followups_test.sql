-- Security audit follow-ups, 28 Sep 2026:
-- 20260928142000 (unused direct writes) and 20260928143000 (active inviter).
begin;
select plan(7);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008501', 'af-driver@example.test', '{"display_name":"Af Driver","mobile_number":"+639170008501"}'),
('00000000-0000-0000-0000-000000008502', 'af-rider@example.test', '{"display_name":"Af Rider","mobile_number":"+639170008502"}'),
('00000000-0000-0000-0000-000000008503', 'af-other@example.test', '{"display_name":"Af Other","mobile_number":"+639170008503"}'),
('00000000-0000-0000-0000-000000008504', 'af-former-admin@example.test', '{"display_name":"Af Former Admin","mobile_number":"+639170008504"}'),
('00000000-0000-0000-0000-000000008505', 'af-invitee@example.test', '{"display_name":"Af Invitee","mobile_number":"+639170008505"}');

insert into public.trips(id, rider_id, status, pickup, dropoff) values
('00000000-0000-0000-0000-000000008511', '00000000-0000-0000-0000-000000008502', 'searching_driver',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326)),
('00000000-0000-0000-0000-000000008512', '00000000-0000-0000-0000-000000008503', 'searching_driver',
 st_setsrid(st_makepoint(121.16,14.2),4326), st_setsrid(st_makepoint(121.17,14.21),4326));
insert into public.ride_share_links(trip_id, created_by) values
('00000000-0000-0000-0000-000000008511', '00000000-0000-0000-0000-000000008502');

-- The inviter was an admin when inviting, and has since been demoted.
insert into public.admin_invites(email, scope, invited_by, token_hash, expires_at) values
('af-invitee@example.test', 'lgu', '00000000-0000-0000-0000-000000008504',
 encode(sha256('af-admin-token'::bytea), 'hex'), now() + interval '1 day');
insert into public.driver_invites(email, toda_zone_id, invited_by, token_hash) values
('af-invitee@example.test', (select id from public.toda_zones where is_active order by code limit 1),
 '00000000-0000-0000-0000-000000008504', encode(sha256('af-driver-token'::bytea), 'hex'));

set local role authenticated;

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008501';
select throws_ok($$insert into public.driver_documents(driver_id, document_type, storage_path, status)
                   values ('00000000-0000-0000-0000-000000008501',
                           (enum_range(null::public.document_type))[1],
                           '00000000-0000-0000-0000-000000008501/x.jpg', 'approved')$$,
  '42501', null, 'a driver cannot record their own document as approved');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008502';
select throws_ok($$update public.ride_share_links set trip_id = '00000000-0000-0000-0000-000000008512'
                   where trip_id = '00000000-0000-0000-0000-000000008511'$$,
  '42501', null, 'a share link cannot be repointed at another rider''s trip');

reset role;
set local role service_role;
select is((select count(*)::int from public.admin_invite_lookup('af-admin-token')), 0,
  'the invite page treats an admin invite from a demoted admin as invalid');
select is((select count(*)::int from public.driver_invite_lookup('af-driver-token')), 0,
  'the invite page treats a driver invite from a demoted admin as invalid');
select throws_ok($$select public.admin_finalize_invited_account('af-admin-token',
                   '00000000-0000-0000-0000-000000008505', 'Af', 'Invitee')$$,
  '42501', null, 'an admin invite from a demoted admin no longer works');
select throws_ok($$select public.driver_finalize_invited_account('af-driver-token',
                   '00000000-0000-0000-0000-000000008505')$$,
  '42501', null, 'a driver invite from a demoted admin no longer works');

reset role;
select is((select role::text from public.profiles where id = '00000000-0000-0000-0000-000000008505'),
  'commuter', 'the invitee was not promoted');

select * from finish();
rollback;
