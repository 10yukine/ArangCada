-- pgTAP: complaints (bidirectional, trip-linked, non-emergency).
--
-- Modelled on 69_phone_verification_test.sql's fixture style and
-- 65_rpc_authorization_test.sql's direct-trip-insert pattern. Every
-- assertion mirrors what 60_live_connected_vertical_slice_test.sql already
-- proves for sos_reports, since create_complaint()/complaints are built as
-- a deliberate structural copy of create_sos_report()/sos_reports.

begin;

select plan(18);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000072a1', 'cpl-rider@example.test',
   '{"display_name":"CPL Rider","mobile_number":"+639170007201"}'::jsonb),
  ('00000000-0000-0000-0000-0000000072b1', 'cpl-driver@example.test',
   '{"display_name":"CPL Driver","mobile_number":"+639170007202"}'::jsonb),
  ('00000000-0000-0000-0000-0000000072d1', 'cpl-stranger@example.test',
   '{"display_name":"CPL Stranger","mobile_number":"+639170007203"}'::jsonb),
  ('00000000-0000-0000-0000-0000000072c1', 'cpl-lgu-admin@example.test',
   '{"display_name":"CPL LGU Admin","mobile_number":"+639170007204"}'::jsonb),
  ('00000000-0000-0000-0000-0000000072c2', 'cpl-other-toda-admin@example.test',
   '{"display_name":"CPL Other TODA Admin","mobile_number":"+639170007205"}'::jsonb),
  ('00000000-0000-0000-0000-0000000072c3', 'cpl-same-toda-admin@example.test',
   '{"display_name":"CPL Same TODA Admin","mobile_number":"+639170007206"}'::jsonb);

update public.profiles set role = 'driver' where id = '00000000-0000-0000-0000-0000000072b1';
update public.profiles set role = 'admin'
 where id in ('00000000-0000-0000-0000-0000000072c1', '00000000-0000-0000-0000-0000000072c2',
              '00000000-0000-0000-0000-0000000072c3');

-- c1 stays an unscoped (citywide) LGU admin. c2 is scoped to a zone the
-- fixture trip is NOT in, to prove cross-zone RLS denial. c3 is scoped to
-- the fixture trip's own zone (CAL-POB-01), to prove update_complaint_status()
-- honours the same has_admin_scope() a TODA admin already reads through --
-- see 20260906020000_complaint_status_admin_scope.sql.
insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000072c2', 'toda', id
  from public.toda_zones
 where code <> 'CAL-POB-01'
 limit 1;

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000072c3', 'toda', id
  from public.toda_zones
 where code = 'CAL-POB-01';

-- Trip A: reached driver_assigned and beyond -- a complaint about it is valid.
insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
   rider_display_name, driver_display_name)
values (
  '00000000-0000-0000-0000-0000000072e1',
  '00000000-0000-0000-0000-0000000072a1',
  '00000000-0000-0000-0000-0000000072b1',
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'special', 'completed',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326),
  'Rider', 'Driver'
);

-- Trip B: cancelled before a driver was ever assigned -- nothing to complain
-- about (matches request_ride: no driver_id is allowed here by the
-- trips_driver_required_after_assignment constraint).
insert into public.trips
  (id, rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
   rider_display_name, driver_display_name)
values (
  '00000000-0000-0000-0000-0000000072e2',
  '00000000-0000-0000-0000-0000000072a1',
  null,
  (select id from public.toda_zones where code = 'CAL-POB-01'),
  'special', 'cancelled_by_rider',
  st_setsrid(st_makepoint(121.165, 14.215), 4326),
  st_setsrid(st_makepoint(121.170, 14.220), 4326),
  'Rider', 'Driver'
);

-- ---------------------------------------------------------------------------
-- Both directions can file
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072a1';

select is(
  (select complainant_role from public.create_complaint(
    '00000000-0000-0000-0000-0000000072e1', 'driver_late',
    'Waited 20 minutes past the confirmed pickup time.', 'cpl-key-0001'
  )),
  'commuter',
  'the rider can file a complaint, role derived server-side as commuter'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072b1';

select is(
  (select complainant_role from public.create_complaint(
    '00000000-0000-0000-0000-0000000072e1', 'passenger_late',
    'Passenger kept the tricycle waiting for 15 minutes.', 'cpl-key-0002'
  )),
  'driver',
  'SECURITY: the driver can also file, role derived server-side as driver -- '
  'bidirectional per the owner''s 5 Sep 2026 decision'
);

-- ---------------------------------------------------------------------------
-- A stranger cannot file about a trip they were never part of
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072d1';

select throws_ok(
  $$select public.create_complaint(
      '00000000-0000-0000-0000-0000000072e1', 'other', 'not my trip', 'cpl-key-0003')$$,
  '42501', null,
  'SECURITY: only a trip participant may file a complaint about it'
);

-- ---------------------------------------------------------------------------
-- A trip that never had a driver assigned refuses -- nothing happened to
-- complain about
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072a1';

select throws_ok(
  $$select public.create_complaint(
      '00000000-0000-0000-0000-0000000072e2', 'other', 'never matched', 'cpl-key-0004')$$,
  '22023', null,
  'a complaint requires a trip that actually had a driver assigned'
);

-- ---------------------------------------------------------------------------
-- Idempotency
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from public.complaints where idempotency_key = 'cpl-key-0001'),
  1,
  'baseline: exactly one row for the first key'
);

select is(
  (select id from public.create_complaint(
    '00000000-0000-0000-0000-0000000072e1', 'driver_late',
    'Waited 20 minutes past the confirmed pickup time.', 'cpl-key-0001'
  )),
  (select id from public.complaints where idempotency_key = 'cpl-key-0001'),
  'replaying the same idempotency key returns the existing row, not a duplicate'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072d1';

select throws_ok(
  $$select public.create_complaint(
      '00000000-0000-0000-0000-0000000072e1', 'other', 'stealing a key', 'cpl-key-0001')$$,
  '42501', null,
  'SECURITY: an idempotency key cannot be replayed by a different complainant'
);

-- ---------------------------------------------------------------------------
-- An unknown category is refused at the schema level
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072a1';

select throws_ok(
  $$select public.create_complaint(
      '00000000-0000-0000-0000-0000000072e1', 'made_up_category', 'x', 'cpl-key-0005')$$,
  '23514', null,
  'an unrecognised category is rejected by the check constraint'
);

-- ---------------------------------------------------------------------------
-- RLS: the respondent cannot read a complaint that names them
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072b1';

select is(
  (select count(*)::integer from public.complaints
    where idempotency_key = 'cpl-key-0001'),
  0,
  'SECURITY: the driver (respondent) cannot select the rider''s complaint '
  'about them -- matches the owner''s "LGU-only" visibility decision'
);

select is(
  (select count(*)::integer from public.complaints
    where idempotency_key = 'cpl-key-0002'),
  1,
  'but the driver CAN select their own filed complaint'
);

-- ---------------------------------------------------------------------------
-- RLS: admin scoping
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072c1';

select is(
  (select count(*)::integer from public.complaints
    where trip_id = '00000000-0000-0000-0000-0000000072e1'),
  2,
  'an unscoped LGU administrator sees both directions on the trip'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072c2';

select is(
  (select count(*)::integer from public.complaints
    where trip_id = '00000000-0000-0000-0000-0000000072e1'),
  0,
  'SECURITY: a TODA administrator scoped to a different zone sees nothing '
  'from this trip''s zone'
);

-- ---------------------------------------------------------------------------
-- Admin status updates
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072a1';

select throws_ok(
  $$select public.update_complaint_status(
      (select id from public.complaints where idempotency_key = 'cpl-key-0001'),
      'acknowledged', null)$$,
  '42501', null,
  'SECURITY: a non-admin cannot update a complaint''s status'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072c1';

select lives_ok(
  $$select public.update_complaint_status(
      (select id from public.complaints where idempotency_key = 'cpl-key-0001'),
      'resolved', 'Spoke with the driver, apologised to the rider.')$$,
  'an admin can update a complaint''s status'
);

select is(
  (select count(*)::integer from public.admin_audit_logs
    where action = 'complaint.resolved'),
  1,
  'the status change wrote exactly one admin_audit_logs row'
);

select throws_ok(
  $$select public.update_complaint_status(
      (select id from public.complaints where idempotency_key = 'cpl-key-0001'),
      'acknowledged', null)$$,
  '22023', null,
  'a resolved complaint cannot be reopened through this action'
);

-- ---------------------------------------------------------------------------
-- Admin status updates: TODA-scoped admin, same class of check as the RLS
-- read policy above -- see 20260906020000_complaint_status_admin_scope.sql
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072c2';

select throws_ok(
  $$select public.update_complaint_status(
      (select id from public.complaints where idempotency_key = 'cpl-key-0002'),
      'acknowledged', null)$$,
  '42501', null,
  'SECURITY: a TODA administrator scoped to a different zone still cannot '
  'update this trip''s zone complaint'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000072c3';

select lives_ok(
  $$select public.update_complaint_status(
      (select id from public.complaints where idempotency_key = 'cpl-key-0002'),
      'investigating', 'Reviewing the driver''s side.')$$,
  'a TODA administrator scoped to this trip''s own zone can update it -- '
  'the bug this migration exists to fix: this used to raise 42501 because '
  'the RPC checked only the global-only is_admin(), not has_admin_scope()'
);

select * from finish();

rollback;
