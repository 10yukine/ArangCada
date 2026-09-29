-- pgTAP: the driver onboarding RPCs.
--
-- WHY THIS FILE EXISTS
--
-- These functions are the only way driver authorization state can change, so
-- they are the whole trust boundary. Three properties matter most and none is
-- visible by reading the schema:
--
--   * a non-admin cannot reach any of them;
--   * a mistyped identifier cannot silently promote an uninvolved commuter;
--   * every state change leaves exactly one admin_audit_logs row.
--
-- The last one is the reason driver_profiles has no admin write policy. If an
-- approval could happen without an audit row, the log would be decorative.

begin;

select plan(48);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000055c1', 'ob-admin@example.test',
     '{"display_name":"Ob Admin","mobile_number":"+639170005501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a1', 'ob-juan@example.test',
     '{"display_name":"Juan Dela Cruz","mobile_number":"+639170005502"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a2', 'ob-maria@example.test',
     '{"display_name":"Maria Santos","mobile_number":"+639170005503"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a3', 'ob-pedro@example.test',
     '{"display_name":"Pedro Reyes","mobile_number":"+639170005504"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a4', 'ob-ana@example.test',
     '{"display_name":"Ana Lim","mobile_number":"+639170005505"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a5', 'ob-suspended@example.test',
     '{"display_name":"Sus Pended","mobile_number":"+639170005506"}'::jsonb),
  ('00000000-0000-0000-0000-0000000055a6', 'ob-fresh@example.test',
     '{"display_name":"Fresh Account","mobile_number":"+639170005507"}'::jsonb);

-- Phone verification (added 31 Aug 2026). can_driver_go_online() and
-- request_ride() now require a verified mobile number, so every fixture
-- account has to be verified or the assertions below fail for a reason that
-- has nothing to do with what they are testing. 69_phone_verification_test.sql
-- is what covers the gate itself.
update public.profiles set phone_verified_at = now()
 where id::text like '%-0000000055__';

update public.profiles set role = 'admin'
 where id = '00000000-0000-0000-0000-0000000055c1';
update public.profiles set status = 'suspended'
 where id = '00000000-0000-0000-0000-0000000055a5';

create temporary table ob_zone as
  select id from public.toda_zones order by code limit 1;

-- Default privileges (00_bootstrap_local.sql) apply only to the public
-- schema; a TEMP table lives in a session-local pg_temp_N schema and never
-- receives them, so authenticated/service_role cannot read it after a role
-- switch unless granted explicitly here.
grant select on ob_zone to authenticated, service_role;

insert into public.toda_members (toda_zone_id, member_name, body_number)
select id, 'Roster Juan', 'OB-001' from ob_zone;

-- ===========================================================================
-- mask_name
-- ===========================================================================
select is(
  public.mask_name('Juan Dela Cruz'), 'J*** D*** C***',
  'mask_name keeps the first letter of each word and hides the rest'
);

select is(
  public.mask_name('  Ana   Lim '), 'A** L**',
  'mask_name collapses irregular whitespace rather than emitting empty words'
);

-- ===========================================================================
-- Every admin RPC refuses a non-admin
-- ===========================================================================

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000055a1';

select throws_ok(
  $$select * from public.admin_preview_driver_candidate('ob-maria@example.test', null)$$,
  '42501', null,
  'a commuter cannot look up another account'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('email', 'ob-maria@example.test', null, 'ob-maria@example.test', null, null, null)$$,
  '42501', null,
  'a commuter cannot promote anybody, including themselves'
);

select throws_ok(
  $$select public.admin_set_profile_status('00000000-0000-0000-0000-0000000055a2', 'suspended', 'x')$$,
  '42501', null,
  'a commuter cannot suspend an account'
);

select throws_ok(
  $$select public.admin_review_driver('00000000-0000-0000-0000-0000000055a2', 'approve', null)$$,
  '42501', null,
  'a commuter cannot approve a driver'
);

-- service_role-only, so an ordinary session must not reach it even as admin
select throws_ok(
  $$select public.admin_activate_new_driver(
      '00000000-0000-0000-0000-0000000055a6',
      '00000000-0000-0000-0000-0000000055c1',
      (select id from ob_zone), null, null)$$,
  '42501', null,
  'a commuter cannot activate a new driver'
);

reset role;

-- ===========================================================================
-- Candidate preview
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000055c1';

select is(
  (select masked_name from public.admin_preview_driver_candidate('ob-juan@example.test', null)),
  'J*** D*** C***',
  'preview returns a masked name, never a readable one'
);

select is(
  (select count(*)::int from public.admin_preview_driver_candidate('nobody@example.test', '+639990000000')),
  0,
  'preview of an unknown email and unknown number returns nothing'
);

-- The discrepancy case: email belongs to one person, phone to another. These
-- must surface as two independent rows so a human resolves it, never merged.
select is(
  (select count(*)::int
     from public.admin_preview_driver_candidate('ob-juan@example.test', '+639170005503')),
  2,
  'an email and a phone matching DIFFERENT accounts return two rows, not one merged guess'
);

select is(
  (select count(*)::int
     from public.admin_preview_driver_candidate('ob-juan@example.test', '+639170005502')),
  2,
  'the same account matched by both identifiers still reports one row per key'
);

-- Formatting must not decide whether a person is found.
select is(
  (select match_key from public.admin_preview_driver_candidate(null, '0917 000 5502')),
  'phone',
  'preview normalises the number it is given, so a locally-formatted number still matches'
);

reset role;
-- ===========================================================================
-- Promotion
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000055c1';

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005502', '9999', (select id from ob_zone), null, null)$$,
  '22023', null,
  'a wrong last-four confirmation refuses the promotion'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('email', 'ob-juan@example.test', null, 'ob-maria@example.test', (select id from ob_zone), null, null)$$,
  '22023', null,
  'an email confirmation that does not match the email given refuses the promotion'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639990000000', '0000', (select id from ob_zone), null, null)$$,
  'P0002', null,
  'promoting an unknown number reports no match rather than creating anything'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005506', '5506', (select id from ob_zone), null, null)$$,
  '22023', null,
  'a suspended account cannot be promoted'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005502', '5502', '00000000-0000-0000-0000-00000000dead', null, null)$$,
  '23503', null,
  'promotion into an unknown TODA zone is refused'
);

-- Happy path, matching the roster on body number.
select lives_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '0917 000 5502', '5502', (select id from ob_zone), 'OB-001', 'FTF onboarding')$$,
  'a correctly confirmed promotion succeeds, and accepts a locally-formatted number'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000055a1'),
  'driver',
  'the promoted account is now a driver'
);

select ok(
  (select toda_member_id is not null from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a1'),
  'the roster entry was linked advisorily because the body number matched'
);

select is(
  (select verification_status::text from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a1'),
  'unverified',
  'a promoted driver starts unverified -- promotion is not approval'
);

select is(
  (select count(*)::int from public.admin_audit_logs
    where action = 'driver.promote'
      and target_profile_id = '00000000-0000-0000-0000-0000000055a1'),
  1,
  'the promotion wrote exactly one audit row'
);

select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005502', '5502', (select id from ob_zone), null, null)$$,
  '22023', null,
  'an account that is already a driver cannot be promoted again'
);

-- Body numbers must stay unique within a zone.
select throws_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005503', '5503', (select id from ob_zone), 'OB-001', null)$$,
  '23505', null,
  'a second driver cannot take a body number already in use in that zone'
);

select lives_ok(
  $$select public.admin_promote_commuter_to_driver('phone', null, '+639170005503', '5503', (select id from ob_zone), null, null)$$,
  'but the same driver can be promoted with no body number at all'
);

select ok(
  (select toda_member_id is null from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a2'),
  'with no body number there is no roster link, and that is not an error'
);

-- ===========================================================================
-- can_driver_go_online, across every state
-- ===========================================================================
select ok(
  not public.can_driver_go_online('00000000-0000-0000-0000-0000000055a1'),
  'an unverified driver cannot go online'
);

-- Documents arrive one at a time; the trigger watches for completion.
-- Written through admin_upsert_driver_document()/admin_review_driver_document()
-- rather than a raw insert/update -- driver_documents_admin_all no longer
-- grants direct writes as of 20260908010000_driver_document_review.sql,
-- exactly so a write like this cannot happen without the audit trail those
-- two RPCs guarantee. The active identity here is still the admin fixture
-- (055c1, set above, unscoped -- has_admin_scope() passes for any zone).
select public.admin_upsert_driver_document('00000000-0000-0000-0000-0000000055a1', 'drivers_license', 'd/a1/lic.jpg');
select public.admin_review_driver_document(
  (select id from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000055a1' and document_type = 'drivers_license'),
  true, null
);
select public.admin_upsert_driver_document('00000000-0000-0000-0000-0000000055a1', 'mtop_franchise', 'd/a1/mtop.jpg');
select public.admin_review_driver_document(
  (select id from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000055a1' and document_type = 'mtop_franchise'),
  true, null
);
select public.admin_upsert_driver_document('00000000-0000-0000-0000-0000000055a1', 'toda_membership', 'd/a1/toda.jpg');
select public.admin_review_driver_document(
  (select id from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000055a1' and document_type = 'toda_membership'),
  true, null
);

select is(
  (select verification_status::text from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a1'),
  'unverified',
  'three of four required documents does not move the driver into review'
);

select throws_ok(
  $$select public.admin_review_driver('00000000-0000-0000-0000-0000000055a1', 'approve', null)$$,
  '22023', null,
  'approval is refused while a required document is missing -- the RPC checks, it does not trust the reviewer'
);

select public.admin_upsert_driver_document('00000000-0000-0000-0000-0000000055a1', 'or_cr', 'd/a1/orcr.jpg');
-- admin_upsert_driver_document() always lands as 'pending' (a fresh
-- upload always needs a fresh review) -- which is exactly the state this
-- fixture wants for the fourth document at this point in the test.

select is(
  (select verification_status::text from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a1'),
  'pending_review',
  'the fourth required document moves the driver into review automatically'
);

select throws_ok(
  $$select public.admin_review_driver('00000000-0000-0000-0000-0000000055a1', 'approve', null)$$,
  '22023', null,
  'all four present is still not enough -- each must itself be approved'
);

select public.admin_review_driver_document(
  (select id from public.driver_documents
    where driver_id = '00000000-0000-0000-0000-0000000055a1' and document_type = 'or_cr'),
  true, null
);

select throws_ok(
  $$select public.admin_review_driver('00000000-0000-0000-0000-0000000055a1', 'reject', null)$$,
  '22023', null,
  'rejecting without a reason is refused'
);

select lives_ok(
  $$select public.admin_review_driver('00000000-0000-0000-0000-0000000055a1', 'approve', null)$$,
  'with every required document approved, the driver is approved'
);

select ok(
  public.can_driver_go_online('00000000-0000-0000-0000-0000000055a1'),
  'an approved, active driver may go online'
);

-- Licence expiry is enforced continuously, with no human in the loop. This
-- fixture mutation cannot run as the impersonated admin: driver_profiles has
-- no admin write policy on purpose (see 20260825120400), so an UPDATE from
-- that session would silently affect zero rows -- the exact silent-failure
-- shape 50_driver_tables_test.sql documents for the same table. Drop
-- impersonation for the direct write, then resume it for the RPC call below.
reset role;
update public.driver_profiles set license_expires_on = current_date - 1
 where id = '00000000-0000-0000-0000-0000000055a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000055c1';

select ok(
  not public.can_driver_go_online('00000000-0000-0000-0000-0000000055a1'),
  'a lapsed licence stops dispatch by itself, without an admin noticing'
);

reset role;
update public.driver_profiles set license_expires_on = current_date + 30
 where id = '00000000-0000-0000-0000-0000000055a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000055c1';

select ok(
  public.can_driver_go_online('00000000-0000-0000-0000-0000000055a1'),
  'a licence valid for another month does not block anything'
);

-- Suspension is the disciplinary tool, and it works at any stage.
select throws_ok(
  $$select public.admin_set_profile_status('00000000-0000-0000-0000-0000000055a1', 'suspended', null)$$,
  '22023', null,
  'suspending without a reason is refused -- the reason is the audit trail'
);

select throws_ok(
  $$select public.admin_set_profile_status('00000000-0000-0000-0000-0000000055c1', 'suspended', 'oops')$$,
  '22023', null,
  'an admin cannot suspend themselves out of the system'
);

select lives_ok(
  $$select public.admin_set_profile_status('00000000-0000-0000-0000-0000000055a1', 'suspended', 'Reported by commuter')$$,
  'an admin can suspend a driver with a reason'
);

select ok(
  not public.can_driver_go_online('00000000-0000-0000-0000-0000000055a1'),
  'a suspended driver cannot go online even while still approved'
);

-- ===========================================================================
-- Demotion is the typo undo, not the disciplinary tool
-- ===========================================================================
select throws_ok(
  $$select public.admin_demote_driver('00000000-0000-0000-0000-0000000055a1', 'wrong person')$$,
  '22023', null,
  'an approved driver cannot be demoted -- suspension exists for that'
);

select lives_ok(
  $$select public.admin_demote_driver('00000000-0000-0000-0000-0000000055a2', 'mistyped number')$$,
  'an unverified driver can be demoted, which is the mis-promotion undo'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000055a2'),
  'commuter',
  'the demoted account is a commuter again'
);

select is(
  (select count(*)::int from public.driver_profiles
    where id = '00000000-0000-0000-0000-0000000055a2'),
  0,
  'and its driver record is gone rather than left orphaned'
);

reset role;
-- ===========================================================================
-- admin_activate_new_driver: reachable only by a trusted server process
-- ===========================================================================
set local role service_role;

select lives_ok(
  $$select public.admin_activate_new_driver(
      '00000000-0000-0000-0000-0000000055a6',
      '00000000-0000-0000-0000-0000000055c1',
      (select id from ob_zone), null, 'created at TODA office')$$,
  'service_role can activate a freshly created account as a driver'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000055a6'),
  'driver',
  'the new account is a driver without ever having been a usable commuter account'
);

select is(
  (select count(*)::int from public.admin_audit_logs
    where action = 'driver.activate'
      and target_profile_id = '00000000-0000-0000-0000-0000000055a6'),
  1,
  'activation wrote exactly one audit row'
);

select throws_ok(
  $$select public.admin_activate_new_driver(
      '00000000-0000-0000-0000-0000000055a4',
      '00000000-0000-0000-0000-0000000055a1',
      (select id from ob_zone), null, null)$$,
  '42501', null,
  'activation refuses an actor who is not an admin, even from service_role'
);

reset role;
select * from finish();

rollback;
