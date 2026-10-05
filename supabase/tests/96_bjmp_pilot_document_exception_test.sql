begin;
select plan(17);
insert into public.toda_zones(id,code,name,boundary,is_active,is_internal_test)
values ('00000000-0000-0000-0000-0000000096a0','CAL-TUR-BJMP','BJMP TODA',
 public.st_geomfromtext('POLYGON((121.15 14.20,121.18 14.20,121.18 14.23,121.15 14.23,121.15 14.20))',4326),true,false);
insert into auth.users(id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000096d1','bjmp-pilot@example.test','{"display_name":"Pilot Driver","mobile_number":"+639170009601"}');
update public.profiles set role='driver',phone_verified_at=now(),status='active'
where id='00000000-0000-0000-0000-0000000096d1';
insert into public.driver_profiles(id,toda_zone_id,verification_status,promoted_by)
values ('00000000-0000-0000-0000-0000000096d1','00000000-0000-0000-0000-0000000096a0','pending_review','00000000-0000-0000-0000-0000000096d1');

update public.bjmp_pilot_settings set enabled=false;
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'BJMP ordinary rules apply when pilot is disabled');
update auth.users set raw_user_meta_data=raw_user_meta_data||'{"bjmp_pilot":true}'
where id='00000000-0000-0000-0000-0000000096d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'user metadata cannot enable the pilot');
update public.bjmp_pilot_settings set enabled=true;
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),true,'enrolled BJMP driver can test without documents or approval');
select is((select verification_status::text from public.driver_profiles where id='00000000-0000-0000-0000-0000000096d1'),'pending_review','pilot does not fabricate ordinary approval');
select is((select count(*)::int from public.driver_documents where driver_id='00000000-0000-0000-0000-0000000096d1'),0,'pilot does not create fake documents');
update public.profiles set phone_verified_at=null where id='00000000-0000-0000-0000-0000000096d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'document exemption does not bypass phone verification');
update public.profiles set phone_verified_at=now(),status='suspended' where id='00000000-0000-0000-0000-0000000096d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'suspended pilot driver stays blocked');
update public.profiles set status='active' where id='00000000-0000-0000-0000-0000000096d1';
update public.driver_profiles set license_expires_on=current_date-1 where id='00000000-0000-0000-0000-0000000096d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'known expired license stays blocked');
update public.driver_profiles set license_expires_on=null where id='00000000-0000-0000-0000-0000000096d1';
update public.toda_zones set is_active=false where code='CAL-TUR-BJMP';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'inactive BJMP stays blocked');
update public.toda_zones set is_active=true where code='CAL-TUR-BJMP';
update public.driver_profiles set toda_zone_id=(select id from public.toda_zones where code='CAL-POB-01') where id='00000000-0000-0000-0000-0000000096d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'other TODAs retain document and approval gates');
update public.driver_profiles set toda_zone_id='00000000-0000-0000-0000-0000000096a0' where id='00000000-0000-0000-0000-0000000096d1';

set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-0000000096d1';
select lives_ok($$select public.set_driver_availability(true,14.215,121.165)$$,'BJMP pilot can go online through the real RPC');
select throws_ok($$select public.set_driver_availability(true,14.40,121.30)$$,'22023',null,'pilot retains Calamba location gate');
select throws_ok($$update public.bjmp_pilot_settings set enabled=false$$,'42501',null,'driver cannot edit pilot settings');
reset role;
select ok(not has_table_privilege('anon','public.bjmp_pilot_settings','UPDATE'),'anonymous users cannot edit pilot settings');
update public.bjmp_pilot_settings set enabled=false;
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000096d1'),false,'revert restores ordinary requirements');
select is((select is_online from public.driver_availability where driver_id='00000000-0000-0000-0000-0000000096d1'),false,'revert immediately takes unapproved driver offline');
select ok((select relrowsecurity from pg_class where oid='public.bjmp_pilot_settings'::regclass),'pilot settings have RLS enabled');
select * from finish();
rollback;
