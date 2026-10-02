-- pgTAP contract for the first connected commuter/driver/admin vertical slice.
-- Every identity, coordinate, and TODA below is synthetic internal-test data.

begin;

select * from no_plan();

select has_table('public', 'admin_scopes', 'administrative scope is persisted');
select has_table('public', 'driver_availability', 'driver availability is persisted');
select has_table('public', 'trip_events', 'critical trip transitions have an audit trail');
select has_table('public', 'trip_messages', 'trip messages are persisted');
select has_table('public', 'sos_reports', 'SOS reports are persisted');
select has_table('public', 'app_evaluation_settings', 'global feedback settings are persisted');
select has_table('public', 'driver_feedback_obligations', 'pending driver feedback survives reconnect');
select has_table('public', 'driver_app_feedback', 'safe feedback results are persisted');

select ok(
  (select bool_and(relrowsecurity)
     from pg_class
    where oid in (
      'public.admin_scopes'::regclass,
      'public.driver_availability'::regclass,
      'public.trip_events'::regclass,
      'public.trip_messages'::regclass,
      'public.sos_reports'::regclass,
      'public.app_evaluation_settings'::regclass,
      'public.driver_feedback_obligations'::regclass,
      'public.driver_app_feedback'::regclass
    )),
  'every exposed vertical-slice table has row-level security enabled'
);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000060a1', 'live-rider@example.test',
   '{"display_name":"Live Rider","mobile_number":"+639170006001"}'::jsonb),
  ('00000000-0000-0000-0000-0000000060b1', 'live-driver@example.test',
   '{"display_name":"Live Driver","mobile_number":"+639170006002"}'::jsonb),
  ('00000000-0000-0000-0000-0000000060c1', 'live-lgu@example.test',
   '{"display_name":"Live LGU","mobile_number":"+639170006003"}'::jsonb),
  ('00000000-0000-0000-0000-0000000060c2', 'live-toda@example.test',
   '{"display_name":"Live TODA","mobile_number":"+639170006004"}'::jsonb),
  ('00000000-0000-0000-0000-0000000060d1', 'live-outsider@example.test',
   '{"display_name":"Live Outsider","mobile_number":"+639170006005"}'::jsonb),
  ('00000000-0000-0000-0000-0000000060c3', 'live-other-toda@example.test',
   '{"display_name":"Other TODA","mobile_number":"+639170006006"}'::jsonb);

update public.profiles
   set role = 'driver', is_internal_tester = true
 where id = '00000000-0000-0000-0000-0000000060b1';

update public.profiles
   set is_internal_tester = true
 where id = '00000000-0000-0000-0000-0000000060a1';

update public.profiles
   set role = 'admin'
 where id in (
   '00000000-0000-0000-0000-0000000060c1',
   '00000000-0000-0000-0000-0000000060c2',
   '00000000-0000-0000-0000-0000000060c3'
 );

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000060c2', 'toda', id
  from public.toda_zones
 where code = 'DEV-SJVTODA-CABUYAO';

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
select '00000000-0000-0000-0000-0000000060c3', 'toda', id
  from public.toda_zones
 where code = 'CAL-CAN-01';

insert into public.driver_profiles (
  id, toda_zone_id, verification_status, body_number, promoted_by
)
select '00000000-0000-0000-0000-0000000060b1', id, 'approved', 'DEV-001',
       '00000000-0000-0000-0000-0000000060c1'
  from public.toda_zones
 where code = 'DEV-SJVTODA-CABUYAO';

-- Dispatch fixtures satisfy the required-document gate.
insert into public.driver_documents (driver_id, document_type, storage_path, status)
select d.id, required.dt, 'test/' || required.dt::text, 'approved'
from public.driver_profiles d
cross join unnest(public.driver_required_document_types()) required(dt)
where d.id::text like '%-0000000060__';


select ok(
  public.is_admin('00000000-0000-0000-0000-0000000060c1'),
  'an unscoped active LGU administrator retains existing global permissions'
);

select ok(
  not public.is_admin('00000000-0000-0000-0000-0000000060c2'),
  'a TODA administrator cannot inherit legacy citywide administrator policies'
);

select ok(
  public.has_admin_scope(
    '00000000-0000-0000-0000-0000000060c2',
    (select id from public.toda_zones where code = 'DEV-SJVTODA-CABUYAO')
  ),
  'a TODA administrator is authorized inside the assigned jurisdiction'
);

select ok(
  not public.has_admin_scope(
    '00000000-0000-0000-0000-0000000060c3',
    (select id from public.toda_zones where code = 'DEV-SJVTODA-CABUYAO')
  ),
  'a TODA administrator has no authority in another jurisdiction'
);

select ok(
  (select is_internal_test from public.toda_zones where code = 'DEV-SJVTODA-CABUYAO'),
  'the SJVTODA/Cabuyao rectangle is visibly marked internal-test only'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060d1';

select throws_ok(
  $$update public.profiles set is_internal_tester = true
     where id = '00000000-0000-0000-0000-0000000060d1'$$,
  null, null,
  'a commuter cannot grant themselves developer-only Cabuyao access'
);

select throws_ok(
  $$select public.request_ride(
      14.2825, 121.1150, 14.2830, 121.1160,
      'Synthetic pickup', 'Synthetic destination', 'unauthorized-cabuyao'
    )$$,
  '42501', null,
  'ordinary accounts cannot request rides in the internal Cabuyao jurisdiction'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060b1';

select lives_ok(
  $$select public.set_driver_availability(true, 14.2825, 121.1150)$$,
  'an approved developer-test driver can go online within SJVTODA'
);

select is(
  (select count(*)::integer from public.driver_availability),
  1,
  'a driver reads their own current location and availability'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060d1';

select is(
  (select count(*)::integer from public.driver_availability),
  0,
  'an unrelated account cannot inspect driver GPS or availability'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060a1';

select lives_ok(
  $$select public.request_ride(
      14.2825, 121.1150, 14.2830, 121.1160,
      'Synthetic pickup', 'Synthetic destination', 'live-booking-001'
    )$$,
  'a developer-test commuter creates an authoritative Special/Cash ride'
);

select is(
  (select status::text from public.trips where idempotency_key = 'live-booking-001'),
  'driver_assigned',
  'the matching online TODA driver receives a targeted request immediately'
);

select is(
  (select driver_id::text from public.trips where idempotency_key = 'live-booking-001'),
  '00000000-0000-0000-0000-0000000060b1',
  'dispatch assigns the approved same-TODA driver server-side'
);

select ok(
  (select accept_by > now()
          and accept_by <= now() + interval '31 seconds'
     from public.trips where idempotency_key = 'live-booking-001'),
  'the offer expires after the approved 30-second acceptance window'
);

select is(
  (select fare_estimate from public.trips where idempotency_key = 'live-booking-001'),
  60.00::numeric,
  'the ordinance-backed Special fare is locked server-side'
);

select is(
  (public.request_ride(
      14.2825, 121.1150, 14.2830, 121.1160,
      'Synthetic pickup', 'Synthetic destination', 'live-booking-001'
    )).id,
  (select id from public.trips where idempotency_key = 'live-booking-001'),
  'retrying the same booking idempotency key returns the original trip'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060d1';

select throws_ok(
  $$select public.accept_ride(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )$$,
  null, null,
  'an unrelated account cannot accept another driver''s offer'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060b1';

select lives_ok(
  $$select public.accept_ride(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )$$,
  'the assigned driver can atomically accept the offer'
);

select is(
  (select status::text from public.trips where idempotency_key = 'live-booking-001'),
  'accepted',
  'both participants observe the same accepted trip'
);

select lives_ok(
  $$select public.send_trip_message(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      'Synthetic driver message'
    )$$,
  'the assigned driver can send a text message after acceptance'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060a1';

select lives_ok(
  $$select public.send_trip_message(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      'Synthetic commuter reply'
    )$$,
  'the commuter can reply in the same trip-scoped conversation'
);

select is(
  (select count(*)::integer from public.trip_messages),
  2,
  'both trip participants see the same persisted two-way chat'
);

select lives_ok(
  $$select public.create_sos_report(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      'Synthetic safety concern', 14.2825, 121.1150, 8.0, 'live-sos-001'
    )$$,
  'a participant can send one explicit trip-linked SOS report'
);

select is(
  (public.create_sos_report(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      'Synthetic safety concern', 14.2825, 121.1150, 8.0, 'live-sos-001'
    )).id,
  (select id from public.sos_reports where idempotency_key = 'live-sos-001'),
  'repeating an SOS idempotency key does not create duplicate reports'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060d1';

select is((select count(*)::integer from public.trip_messages), 0,
  'an unrelated user cannot read a private commuter-driver conversation');
select is((select count(*)::integer from public.sos_reports), 0,
  'an unrelated user cannot read somebody else''s safety report');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c3';

select is((select count(*)::integer from public.sos_reports), 0,
  'a different TODA cannot see an SJVTODA safety report');
select is((select count(*)::integer from public.driver_availability), 0,
  'a different TODA cannot see an SJVTODA driver GPS point');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c2';

select is((select count(*)::integer from public.sos_reports), 1,
  'the assigned TODA administrator sees the report live');
select is((select count(*)::integer from public.trip_messages), 0,
  'a TODA administrator cannot browse ordinary private chat');
select is((select count(*)::integer from public.trips), 1,
  'a TODA administrator reads only its own jurisdiction''s trip');

select throws_ok(
  $$select public.update_sos_status(
      (select id from public.sos_reports where idempotency_key = 'live-sos-001'),
      'resolved', 'Not authorized'
    )$$,
  '42501', null,
  'TODA administrators may read SOS reports but cannot resolve them'
);

select throws_ok(
  $$select public.update_feedback_settings(2, 10, true)$$,
  '42501', null,
  'TODA administrators cannot change the global driver-feedback interval'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c1';

select is((select count(*)::integer from public.trip_messages), 0,
  'even an LGU administrator cannot browse an unreported conversation');

select lives_ok(
  $$select public.update_sos_status(
      (select id from public.sos_reports where idempotency_key = 'live-sos-001'),
      'acknowledged', 'Synthetic LGU acknowledgment'
    )$$,
  'an LGU administrator may acknowledge and audit an SOS report'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060b1';

select lives_ok(
  $$select public.mark_arrived(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )$$,
  'the assigned driver can mark pickup arrival'
);

select lives_ok(
  $$select public.start_trip(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )$$,
  'the assigned driver can start the accepted trip'
);

select lives_ok(
  $$select public.publish_driver_location(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      14.2830, 121.1160, 6.0
    )$$,
  'the active driver publishes one current GPS point at the destination'
);

select ok(
  (select completion_available_at > now() + interval '59 seconds'
          and completion_available_at <= now() + interval '61 seconds'
     from public.trips where idempotency_key = 'live-booking-001'),
  'destination proximity starts a server-owned 60-second completion countdown'
);

select lives_ok(
  $$select public.complete_trip(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )$$,
  'the assigned driver can complete the shared trip exactly once'
);

select is(
  (select final_fare from public.trips where idempotency_key = 'live-booking-001'),
  60.00::numeric,
  'completion preserves the locked fare, including for an early drop-off'
);

select is(
  (public.complete_trip(
      (select id from public.trips where idempotency_key = 'live-booking-001')
    )).id,
  (select id from public.trips where idempotency_key = 'live-booking-001'),
  'duplicate trip completion is idempotent'
);

select is(
  (select count(*)::integer from public.driver_feedback_obligations
    where submitted_at is null),
  1,
  'a completed trip creates exactly one durable mandatory feedback obligation'
);

select throws_ok(
  $$select public.set_driver_availability(true, 14.2825, 121.1150)$$,
  '42501', null,
  'pending mandatory app feedback prevents the driver from going online'
);

select throws_ok(
  $$select public.send_trip_message(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      'Should not send after completion'
    )$$,
  '22023', null,
  'trip completion locks new chat messages'
);

select is((select count(*)::integer from public.trip_messages), 2,
  'the completed conversation remains readable during its 30-day retention period');

select throws_ok(
  $$select public.submit_driver_feedback(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      '{"ease_of_use":6}'::jsonb, null, true
    )$$,
  '22023', null,
  'feedback rejects incomplete instruments and ratings outside the five-point scale'
);

select lives_ok(
  $$select public.submit_driver_feedback(
      (select id from public.trips where idempotency_key = 'live-booking-001'),
      '{"ease_of_use":5,"booking_clarity":4,"navigation_clarity":4,"fare_fairness":5,"reliability":4,"safety_confidence":5,"continued_use":5}'::jsonb,
      'Synthetic anonymous comment', true
    )$$,
  'a driver can submit all seven required bilingual Likert answers anonymously'
);

select ok(
  not (public.get_driver_feedback_state() ->> 'pending')::boolean,
  'submitting the response clears the durable mandatory feedback state'
);

select lives_ok(
  $$select public.set_driver_availability(true, 14.2825, 121.1150)$$,
  'the driver may resume dispatch only after feedback is submitted'
);

reset role;

-- An admin who can read both tables must not be able to join an anonymous
-- response to its driver (20261002092000).
select is(
  (select count(*)::integer from public.trip_events
    where event_type = 'evaluation.driver_feedback_submitted'),
  0,
  'an anonymous evaluation leaves no event naming the driver and the trip'
);

select is(
  (select submitted_at from public.driver_app_feedback
    where comment = 'Synthetic anonymous comment'),
  date_trunc('day', now(), 'Asia/Manila'),
  'and records the day it was submitted, not the instant'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c2';

select is((select count(*)::integer from public.driver_app_feedback), 1,
  'the assigned TODA sees its submitted driver app evaluation');

select ok(
  (select is_anonymous and driver_display_name is null
     from public.driver_app_feedback),
  'anonymous evaluation rows expose neither a driver name nor a driver identifier'
);

select is(
  (select unique_driver_count::integer from public.get_feedback_summary(null)),
  1,
  'TODA participation progress counts one unique driver independently of response totals'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c3';

select is((select count(*)::integer from public.driver_app_feedback), 0,
  'another TODA cannot inspect SJVTODA driver responses');

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000060c1';

select lives_ok(
  $$select public.update_feedback_settings(2, 12, true)$$,
  'only the LGU may change the global interval and per-TODA participation target'
);

select is((select feedback_interval from public.app_evaluation_settings), 2,
  'the new LGU-controlled interval is persisted for all connected clients');

reset role;

select * from finish();

rollback;
