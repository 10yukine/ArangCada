begin;
select plan(11);
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000080d1','gate-driver@example.test','{"display_name":"Gate Driver","mobile_number":"+639170008001"}');
update public.profiles set role='driver', phone_verified_at=now()
where id='00000000-0000-0000-0000-0000000080d1';
insert into public.driver_profiles (id,toda_zone_id,body_number,plate_number,verification_status,promoted_by)
select '00000000-0000-0000-0000-0000000080d1',id,'GATE','GATE-001','approved','00000000-0000-0000-0000-0000000080d1'
from public.toda_zones where is_active limit 1;
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'approval alone is insufficient');
insert into public.driver_documents(driver_id,document_type,storage_path,status)
select '00000000-0000-0000-0000-0000000080d1',dt,'test/'||dt::text,'approved'
from unnest(public.driver_required_document_types()) dt;
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),true,'approved driver with all reviewed documents may go online');
insert into public.driver_availability(driver_id,toda_zone_id,is_online)
select id,toda_zone_id,true from public.driver_profiles where id='00000000-0000-0000-0000-0000000080d1';
update public.driver_documents set status='pending' where driver_id='00000000-0000-0000-0000-0000000080d1' and document_type='or_cr';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'replacement awaiting review blocks availability');
select is((select is_online from public.driver_availability where driver_id='00000000-0000-0000-0000-0000000080d1'),false,'document revocation immediately takes driver offline');
update public.driver_documents set status='approved' where driver_id='00000000-0000-0000-0000-0000000080d1';
update public.driver_profiles set verification_status='pending_review' where id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'documents alone do not replace driver approval');
update public.profiles set is_internal_tester=true where id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'ordinary internal testers cannot bypass approval');
update auth.users set raw_user_meta_data=raw_user_meta_data||'{"driver_approval_test_bypass":true}' where id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'client metadata cannot grant the exception');
update auth.users set raw_app_meta_data='{"driver_approval_test_bypass":true}' where id='00000000-0000-0000-0000-0000000080d1';
delete from public.driver_documents where driver_id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),true,'server-provisioned owner exception bypasses documents and approval');
update public.profiles set status='suspended' where id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'exception never bypasses suspension');
update public.profiles set status='active' where id='00000000-0000-0000-0000-0000000080d1';
update public.driver_profiles set license_expires_on=current_date-1 where id='00000000-0000-0000-0000-0000000080d1';
select is(public.can_driver_go_online('00000000-0000-0000-0000-0000000080d1'),false,'exception never bypasses expiry');
update public.profiles set role='admin' where id='00000000-0000-0000-0000-0000000080d1';
set local role authenticated;
set local request.jwt.claim.sub='00000000-0000-0000-0000-0000000080d1';
select throws_ok($$select public.admin_review_driver('00000000-0000-0000-0000-0000000080d1','reject','test')$$,
 '22023', null, 'enrolled driver rejection is rejected by the server');
select * from finish();
rollback;
