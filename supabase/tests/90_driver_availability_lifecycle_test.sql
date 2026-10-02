-- pgTAP: dispatch offers a ride only to a driver whose app reported recently
-- and who holds no live trip (20261002090000).
--
--   pickup        (121.165, 14.215)  inside CAL-POB-01
--   driver NEAR   ~150 m from the pickup
--   driver FAR    ~550 m from the pickup
--
-- Every assertion from "the fresh driver is assigned" down fails on the schema
-- before that migration.
begin;

select plan(23);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000090a1', 'lc-rider-1@example.test',
   '{"display_name":"LC Rider 1","mobile_number":"+639170009001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000090a2', 'lc-rider-2@example.test',
   '{"display_name":"LC Rider 2","mobile_number":"+639170009002"}'::jsonb),
  ('00000000-0000-0000-0000-0000000090a3', 'lc-rider-3@example.test',
   '{"display_name":"LC Rider 3","mobile_number":"+639170009003"}'::jsonb),
  ('00000000-0000-0000-0000-0000000090b1', 'lc-near@example.test',
   '{"display_name":"LC Near","mobile_number":"+639170009004"}'::jsonb),
  ('00000000-0000-0000-0000-0000000090b2', 'lc-far@example.test',
   '{"display_name":"LC Far","mobile_number":"+639170009005"}'::jsonb);

update public.profiles
   set role = case when id::text like '%b_' then 'driver' else 'commuter' end::public.user_role,
       status = 'active',
       phone_verified_at = now()
 where id::text like '%-0000000090__';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status)
select p.id, (select id from public.toda_zones where code = 'CAL-POB-01'),
       '00000000-0000-0000-0000-0000000090a1', 'approved'
  from public.profiles p
 where p.id::text like '%-0000000090b_'
on conflict (id) do nothing;

insert into public.driver_documents (driver_id, document_type, storage_path, status)
select d.id, required.dt, 'test/' || required.dt::text, 'approved'
  from public.driver_profiles d
 cross join unnest(public.driver_required_document_types()) required(dt)
 where d.id::text like '%-0000000090b_';

insert into public.driver_availability
  (driver_id, toda_zone_id, is_online, latitude, longitude) values
  ('00000000-0000-0000-0000-0000000090b1',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2160, 121.1660),
  ('00000000-0000-0000-0000-0000000090b2',
   (select id from public.toda_zones where code = 'CAL-POB-01'),
   true, 14.2190, 121.1680)
on conflict (driver_id) do update
  set is_online = true,
      latitude  = excluded.latitude,
      longitude = excluded.longitude;

select is((select driver_fresh_seconds from public.dispatch_settings where id), 90,
  'a driver must have reported within 90 seconds by default');
select throws_ok(
  $$update public.dispatch_settings set driver_fresh_seconds = 20 where id$$,
  '23514', null, 'the window cannot be set below 30 seconds');

-- NEAR's app went away ten minutes ago without going offline. ---------------
update public.driver_availability set last_seen_at = now() - interval '10 minutes'
 where driver_id = '00000000-0000-0000-0000-0000000090b1';

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a1';
select lives_ok(
  $$select public.request_ride(14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'lc-key-1')$$,
  'rider 1 books');
reset role;
select is((select driver_id from public.trips where idempotency_key = 'lc-key-1'),
  '00000000-0000-0000-0000-0000000090b2'::uuid,
  'the fresh driver is assigned although the stale one is nearer');

-- Only the stale driver is left. --------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a2';
select is(
  (select status::text from public.request_ride(14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'lc-key-2')),
  'searching_driver', 'request_ride does not offer the ride to a stale driver');
select is(
  (select status::text from public.retry_dispatch(
      (select id from public.trips where idempotency_key = 'lc-key-2'))),
  'searching_driver', 'nor does retry_dispatch');

-- NEAR's app comes back: one heartbeat makes the driver dispatchable. --------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090b1';
select is(
  (select last_seen_at from public.set_driver_availability(true, 14.2160, 121.1660)),
  now(), 'a heartbeat stamps last_seen_at');
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a2';
select is(
  (select driver_id from public.retry_dispatch(
      (select id from public.trips where idempotency_key = 'lc-key-2'))),
  '00000000-0000-0000-0000-0000000090b1'::uuid,
  'and the next retry assigns that driver');

-- NEAR ignores the offer and goes away again. An expired offer sets the driver
-- online, but must not make them look present.
reset role;
update public.driver_availability set last_seen_at = now() - interval '10 minutes'
 where driver_id = '00000000-0000-0000-0000-0000000090b1';
update public.trips set accept_by = now() - interval '1 second'
 where idempotency_key = 'lc-key-2';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a2';
select is(
  (select status::text from public.expire_ride(
      (select id from public.trips where idempotency_key = 'lc-key-2'))),
  'no_driver_available', 'the unanswered offer expires');
reset role;
select ok(
  (select is_online from public.driver_availability
    where driver_id = '00000000-0000-0000-0000-0000000090b1'),
  'expire_ride still sets the driver online');
select is(
  (select last_seen_at from public.driver_availability
    where driver_id = '00000000-0000-0000-0000-0000000090b1'),
  now() - interval '10 minutes', 'but leaves last_seen_at alone');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a2';
select is(
  (select status::text from public.request_ride(14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'lc-key-3')),
  'searching_driver', 'so the next booking is not offered to the same absent driver');

-- FAR holds rider 1's trip. A raced heartbeat left the row online. ------------
reset role;
update public.driver_availability set is_online = true
 where driver_id = '00000000-0000-0000-0000-0000000090b2';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a3';
select lives_ok(
  $$select public.request_ride(14.215, 121.165, 14.220, 121.170,
      'Pickup', 'Destination', 'lc-key-4')$$,
  'a booking beside a busy driver flagged online does not fail');
select is(
  (select status::text from public.trips where idempotency_key = 'lc-key-4'),
  'searching_driver', 'it keeps searching');
select lives_ok(
  $$select public.retry_dispatch(
      (select id from public.trips where idempotency_key = 'lc-key-4'))$$,
  'and retry_dispatch does not fail either');
select is(
  (select status::text from public.trips where idempotency_key = 'lc-key-4'),
  'searching_driver', 'it still keeps searching');

-- The busy driver's own heartbeat is refused; the trip heartbeat counts. ------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090b2';
select throws_ok(
  $$select public.set_driver_availability(true, 14.2190, 121.1680)$$,
  '22023', 'a driver cannot receive a second active trip',
  'a driver holding a trip cannot mark themselves available');
reset role;
update public.driver_availability set last_seen_at = now() - interval '10 minutes'
 where driver_id = '00000000-0000-0000-0000-0000000090b2';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090b2';
select is(
  (select last_seen_at from public.publish_driver_location(
      (select id from public.trips where idempotency_key = 'lc-key-1'),
      14.2190, 121.1680, 5)),
  now(), 'publishing a trip location stamps last_seen_at');
-- 20261002095000: NaN sorts above every number, so "< 0" alone let it through.
select throws_ok(
  $$select public.publish_driver_location(
      (select id from public.trips where idempotency_key = 'lc-key-1'),
      14.2190, 121.1680, 'NaN')$$,
  '22023', null, 'a GPS accuracy that is not a real distance is refused');
reset role;

-- The race itself needs two sessions; this pins the lock that closes it.
select ok(
  position('for update' in pg_get_functiondef(
    'public.set_driver_availability(boolean,double precision,double precision)'::regprocedure))
  between 1 and position('from public.trips t' in pg_get_functiondef(
    'public.set_driver_availability(boolean,double precision,double precision)'::regprocedure)),
  'set_driver_availability locks the driver''s row before it looks for a live trip');

-- The migration's data heal, repeated here because fixtures arrive after it.
select is(
  (select count(*)::int from public.driver_availability a
    where a.driver_id = '00000000-0000-0000-0000-0000000090b2' and a.is_online),
  1, 'fixture: the busy driver is still flagged online');
select is(
  (select count(*)::int from public.driver_availability
    where driver_id = '00000000-0000-0000-0000-0000000090b1'
      and last_seen_at > now() - interval '90 seconds'),
  0, 'and the absent one is still stale');

-- The admin console reads the same rule: is_online alone is not "online".
update public.profiles set role = 'admin'
 where id = '00000000-0000-0000-0000-0000000090a3';
insert into public.admin_scopes (admin_id, scope)
values ('00000000-0000-0000-0000-0000000090a3', 'lgu');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000090a3';
select is(
  (select is_online from public.admin_list_drivers()
    where driver_id = '00000000-0000-0000-0000-0000000090b1'),
  false, 'the admin driver list does not show an absent driver as online');
reset role;

select * from finish();
rollback;
