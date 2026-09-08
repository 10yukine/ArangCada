-- pgTAP: driver document Storage bucket + the two audited admin RPCs
-- (upload/replace, review) added by 20260908010000_driver_document_review.sql.
--
-- WHY THIS FILE EXISTS
--
-- driver_documents_admin_all used to grant admin blanket insert/update/
-- delete on the table directly, no audit row required. This migration
-- narrows that to select-only and moves every write behind
-- admin_upsert_driver_document()/admin_review_driver_document() --
-- exactly so a write cannot happen without an admin_audit_logs row. That
-- property, the TODA scoping (matching admin_review_scoped_driver's own
-- shape), and the new Storage bucket's owner-or-admin read are what this
-- file actually proves; none is visible from reading the schema alone.

begin;

select plan(19);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000076a1', 'ddr-driver@example.test',
   '{"display_name":"DDR Driver","mobile_number":"+639170007601"}'::jsonb),
  ('00000000-0000-0000-0000-0000000076c1', 'ddr-lgu-admin@example.test',
   '{"display_name":"DDR LGU Admin","mobile_number":"+639170007602"}'::jsonb),
  ('00000000-0000-0000-0000-0000000076c2', 'ddr-same-toda-admin@example.test',
   '{"display_name":"DDR Same TODA Admin","mobile_number":"+639170007603"}'::jsonb),
  ('00000000-0000-0000-0000-0000000076c3', 'ddr-other-toda-admin@example.test',
   '{"display_name":"DDR Other TODA Admin","mobile_number":"+639170007604"}'::jsonb),
  ('00000000-0000-0000-0000-0000000076d1', 'ddr-stranger@example.test',
   '{"display_name":"DDR Stranger","mobile_number":"+639170007605"}'::jsonb);

update public.profiles set role = 'admin'
 where id in (
   '00000000-0000-0000-0000-0000000076c1',
   '00000000-0000-0000-0000-0000000076c2',
   '00000000-0000-0000-0000-0000000076c3'
 );

-- c1 stays an unscoped (citywide) LGU admin. c2 is scoped to the driver's
-- own zone; c3 to a different one, to prove TODA scoping the same way
-- 72_complaints_test.sql already does for update_complaint_status().
insert into public.driver_profiles (id, toda_zone_id, body_number, promoted_by)
select '00000000-0000-0000-0000-0000000076a1', id, 'DDR-1',
       '00000000-0000-0000-0000-0000000076c1'
  from public.toda_zones where code = 'CAL-POB-01';

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000076c2', 'toda', id
  from public.toda_zones where code = 'CAL-POB-01';

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000076c3', 'toda', id
  from public.toda_zones where code <> 'CAL-POB-01' limit 1;

-- ---------------------------------------------------------------------------
-- admin_upsert_driver_document(): authorization
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076d1';

select throws_ok(
  $$select public.admin_upsert_driver_document(
      '00000000-0000-0000-0000-0000000076a1', 'drivers_license', '76a1/drivers_license-1.jpg')$$,
  '42501', null,
  'SECURITY: a non-admin cannot upload a driver document'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c3';

select throws_ok(
  $$select public.admin_upsert_driver_document(
      '00000000-0000-0000-0000-0000000076a1', 'drivers_license', '76a1/drivers_license-1.jpg')$$,
  '42501', null,
  'SECURITY: an admin scoped to a different TODA cannot upload for this driver'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c2';

select is(
  (select status::text from public.admin_upsert_driver_document(
      '00000000-0000-0000-0000-0000000076a1', 'drivers_license', '76a1/drivers_license-1.jpg')),
  'pending',
  'a same-TODA-scoped admin can upload a document, and it lands as pending'
);

-- admin_audit_logs_select_admin (a pre-existing, unrelated policy this
-- migration does not touch) gates on the plain is_admin() -- which, like
-- has_admin_scope() relies on, excludes any TODA-scoped admin by
-- definition. Reading it back as 076c2 (still active from the upload
-- above) would read 0 rows for that reason, not because nothing was
-- written -- same identity-switch lesson as
-- 72_complaints_test.sql/74_fare_class_claims_test.sql. Switch to the
-- unscoped LGU admin before reading.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c1';

select is(
  (select count(*)::integer from public.admin_audit_logs
    where action = 'driver_document.uploaded'),
  1,
  'the upload wrote exactly one admin_audit_logs row'
);

-- Captured once, as the unscoped admin (076c1, active here), and reused
-- below instead of re-deriving the id under each test identity own
-- restricted RLS view -- deriving it fresh per-identity returned NULL for
-- a correctly-blocked caller (NULL never equals any real id), which made
-- admin_review_driver_document raise document-does-not-exist instead of
-- the 42501 those assertions are actually trying to prove.
create temporary table ddr_doc as
  select id from public.driver_documents
   where driver_id = '00000000-0000-0000-0000-0000000076a1' and document_type = 'drivers_license';
grant select on ddr_doc to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Replace-and-reset: uploading again for the same type resets to pending
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c1';

select public.admin_review_driver_document(
  (select id from ddr_doc),
  true, null
);

select is(
  (select status::text from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000076a1' and document_type = 'drivers_license'),
  'approved',
  'baseline: the document is now approved'
);

select is(
  (select status::text from public.admin_upsert_driver_document(
      '00000000-0000-0000-0000-0000000076a1', 'drivers_license', '76a1/drivers_license-2.jpg')),
  'pending',
  'uploading a replacement for an already-approved type resets it to pending'
);

select is(
  (select storage_path from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000076a1' and document_type = 'drivers_license'),
  '76a1/drivers_license-2.jpg',
  'and the storage_path is the new one, not appended alongside the old'
);

select is(
  (select reviewed_by from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000076a1' and document_type = 'drivers_license'),
  null,
  'reviewed_by is cleared by the reset, not left pointing at the old reviewer'
);

select is(
  (select count(*)::integer from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000076a1' and document_type = 'drivers_license'),
  1,
  'still exactly one row for this driver+type -- replace, not a second row'
);

-- ---------------------------------------------------------------------------
-- admin_review_driver_document(): authorization and validation
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076d1';

select throws_ok(
  $$select public.admin_review_driver_document(
      (select id from ddr_doc),
      true, null)$$,
  '42501', null,
  'SECURITY: a non-admin cannot review a driver document'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c3';

select throws_ok(
  $$select public.admin_review_driver_document(
      (select id from ddr_doc),
      true, null)$$,
  '42501', null,
  'SECURITY: an admin scoped to a different TODA cannot review this driver''s document either'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c1';

select throws_ok(
  $$select public.admin_review_driver_document(
      (select id from ddr_doc),
      false, null)$$,
  '22023', null,
  'rejecting without a reason is refused, same as update_complaint_status''s sibling constraint'
);

select is(
  (select status::text from public.admin_review_driver_document(
      (select id from ddr_doc),
      false, 'Photo is blurry, resubmit.')),
  'rejected',
  'rejecting with a reason succeeds'
);

select is(
  (select count(*)::integer from public.admin_audit_logs
    where action = 'driver_document.rejected'),
  1,
  'the rejection wrote exactly one admin_audit_logs row'
);

-- ---------------------------------------------------------------------------
-- Storage: driver-documents bucket, owner-or-admin read, admin-only write
-- ---------------------------------------------------------------------------
select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'driver-documents',
      '00000000-0000-0000-0000-0000000076a1/drivers_license-2.jpg',
      '00000000-0000-0000-0000-0000000076c1')$$,
  'an admin can upload into the driver-documents bucket'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076a1';

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'driver-documents',
      '00000000-0000-0000-0000-0000000076a1/self-uploaded.jpg',
      '00000000-0000-0000-0000-0000000076a1')$$,
  '42501', null,
  'SECURITY: the driver themself cannot upload into driver-documents -- admin-only this pass'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000076a1/drivers_license-2.jpg'),
  1,
  'the owning driver CAN select their own uploaded document'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076d1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000076a1/drivers_license-2.jpg'),
  0,
  'SECURITY: a stranger cannot select another driver''s document'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000076c1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000076a1/drivers_license-2.jpg'),
  1,
  'and an admin can select any driver''s document'
);

select * from finish();

rollback;
