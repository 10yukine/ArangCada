-- Local-only regression for the staged proposal; no hosted database required.
begin;
select no_plan();
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000100a1', 'pl-rider@example.test',
   '{"display_name":"PL Rider","mobile_number":"+639170010001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000100b1', 'pl-driver@example.test',
   '{"display_name":"PL Driver","mobile_number":"+639170010002"}'::jsonb);

update public.profiles
   set role = case when id::text like '%b_' then 'driver' else 'commuter' end::public.user_role,
       status = 'active',
       phone_verified_at = now()
 where id::text like '%-0000000100__';

insert into public.driver_profiles (id, toda_zone_id, promoted_by, verification_status)
values ('00000000-0000-0000-0000-0000000100b1',
        (select id from public.toda_zones where code = 'CAL-CAN-01'),
        '00000000-0000-0000-0000-0000000100a1', 'approved')
on conflict (id) do nothing;

insert into public.driver_documents (driver_id, document_type, storage_path, status)
select '00000000-0000-0000-0000-0000000100b1', required.dt, 'test/' || required.dt::text, 'approved'
  from unnest(public.driver_required_document_types()) required(dt);


select is((select app_fare_enabled from public.mobile_settings where id), false, 'proposed policy defaults off');
update public.mobile_settings set app_fare_enabled = true;
select is(public.get_mobile_settings()->>'app_fare_enabled', 'true', 'mobile previews see the staged policy');
select is(public.get_mobile_settings()->>'pickup_charge_max_m', '2500', 'combined pickup cap is explicit, independent of search widening');

-- Quote all party sizes on a minimum-distance trip, with no driver available.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select throws_ok($$ select public.request_ride(14.185,121.0724,14.185,121.074,'P','D','old-client') $$, '22023', 'Fares changed. Reopen the app and review your fare before booking.', 'a stale preview or old client cannot silently book the new policy');
select public.request_ride(14.185,121.0724,14.185,121.074,'Pickup','Dropoff','app-one',1);
reset role;
update public.trips set status = 'cancelled_by_rider' where idempotency_key='app-one';
set local role authenticated;
select public.request_ride(14.185,121.0724,14.185,121.074,'Pickup','Dropoff','app-two',2);
reset role;
update public.trips set status = 'cancelled_by_rider' where idempotency_key='app-two';
set local role authenticated;
select public.request_ride(14.185,121.0724,14.185,121.074,'Pickup','Dropoff','app-three',3);
reset role;
update public.trips set status = 'cancelled_by_rider' where idempotency_key='app-three';
set local role authenticated;
select public.request_ride(14.185,121.0724,14.185,121.074,'Pickup','Dropoff','app-four',4);
select throws_ok($$ select public.request_ride(14.185,121.0724,14.185,121.074,'P','D','bad-count',5) $$,
  '22023', 'passenger count must be between 1 and 4', 'server rejects a fifth passenger');
select throws_ok($$ select public.request_ride(14.185,121.0724,14.185,121.074,'P','D','bad-count',0) $$,
  '22023', 'passenger count must be between 1 and 4', 'server rejects zero passengers');
select is((public.request_ride(14.185,121.0724,14.185,121.074,'P','D','app-four',1)).passenger_count, 4,
  'idempotent retry retains the original passenger count and quote');
select throws_ok($$ update public.mobile_settings set app_fare_enabled=false $$, '42501', null, 'client cannot switch tariff');
select throws_ok($$ select public.set_trip_passenger_count((select id from public.trips where idempotency_key='app-four'), 1) $$, '22023', 'cancel and book again to change the quoted passenger count', 'a quoted passenger tier cannot be changed without rebooking');
reset role;
select results_eq(
  $$select passenger_count, base_trip_fare, service_supplement, system_fee, fare_estimate
      from public.trips where idempotency_key like 'app-%' order by passenger_count$$,
  $$values (1,60::numeric,10::numeric,5::numeric,75::numeric),
           (2,60::numeric,10::numeric,5::numeric,75::numeric),
           (3,60::numeric,15::numeric,5::numeric,80::numeric),
           (4,60::numeric,20::numeric,5::numeric,85::numeric)$$,
  'minimum full fares match the proposal for all party sizes');

-- A pending quote is a snapshot: turning the switch off or approving a
-- discount cannot change its fare class, fee or premium at later assignment.
update public.trips set requested_at=now()-interval '4 minutes' where idempotency_key='app-four';
update public.mobile_settings set app_fare_enabled=false;
update public.profiles set fare_class='discounted' where id='00000000-0000-0000-0000-0000000100a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100b1';
select public.set_driver_availability(true,14.185,121.0557);
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000100a1';
select public.retry_dispatch((select id from public.trips where idempotency_key='app-four'));
reset role;
select results_eq(
  $$select fare_estimate, service_supplement, system_fee, pickup_fare from public.trips where idempotency_key='app-four'$$,
  $$values (85::numeric,20::numeric,5::numeric,10::numeric)$$,
  'far pickup is covered by the existing premium, with original full-fare class and fee');
update public.trips set status='cancelled_by_rider' where idempotency_key='app-four';
update public.driver_availability set is_online=false;

-- Discounted minimum: literal base 48 + premium16 + system4, not 80% of
-- a recomputed ordinance formula. Config changes do not backdate old quotes.
update public.mobile_settings set app_fare_enabled=true;
set local role authenticated;
select public.request_ride(14.185,121.0724,14.185,121.074,'P','D','app-discount',4);
reset role;
select results_eq(
  $$select base_trip_fare,service_supplement,system_fee,fare_estimate from public.trips where idempotency_key='app-discount'$$,
  $$values (48::numeric,16::numeric,4::numeric,68::numeric)$$,
  'discounted minimum uses approved class, discounted premium and system fee');
select is((select fare_estimate from public.trips where idempotency_key='app-one'),75::numeric,'older quote is unchanged');
select ok(not has_function_privilege('anon', 'public.request_ride(double precision,double precision,double precision,double precision,text,text,text,integer)', 'EXECUTE'), 'anonymous caller cannot request rides');
select ok(not has_function_privilege('authenticated', 'public.trips_snapshot_app_fare()', 'EXECUTE'), 'snapshot trigger is internal');

-- A larger future search radius must not expand the agreed pickup ceiling.
update public.trips set status='cancelled_by_rider' where idempotency_key='app-discount';
update public.profiles set fare_class='standard' where id='00000000-0000-0000-0000-0000000100a1';
set local role authenticated;
select public.request_ride(14.185,121.0724,14.185,121.074,'P','D','app-cap',1);
reset role;
update public.trips set requested_at=now()-interval '4 minutes' where idempotency_key='app-cap';
update public.dispatch_settings set widened_radius_m=5000;
update public.driver_availability set is_online=true,latitude=14.185,longitude=121.0400,last_seen_at=now();
set local role authenticated;
select public.retry_dispatch((select id from public.trips where idempotency_key='app-cap'));
reset role;
select results_eq(
  $$select status::text,service_supplement,system_fee,pickup_fare,fare_estimate from public.trips where idempotency_key='app-cap'$$,
  $$values ('driver_assigned',20::numeric,5::numeric,20::numeric,85::numeric)$$,
  'a larger pickup replaces the premium and stays capped even if dispatch expands');
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-0000000100b1';
select public.accept_ride((select id from public.trips where idempotency_key='app-cap'));
reset role;
update public.trips set status='in_progress' where idempotency_key='app-cap';
update public.mobile_settings set app_fare_enabled=false;
set local role authenticated;
select public.publish_driver_location((select id from public.trips where idempotency_key='app-cap'),14.185,121.074,5);
select public.complete_trip((select id from public.trips where idempotency_key='app-cap'));
reset role;
select results_eq(
  $$select final_fare, final_fare-system_fee, system_fee from public.trips where idempotency_key='app-cap'$$,
  $$values (85::numeric,80::numeric,5::numeric)$$,
  'completion retains the quoted passenger total, driver share and fee after disabling the policy');
select * from finish();
rollback;
