-- Account audit and cleanup — run in the Supabase SQL Editor
--
-- Purpose: before the pilot beta, remove test/fake accounts from the hosted
-- project while preserving the one real account.
--
-- ============================================================================
-- !! DO NOT RUN THIS YET -- DEFERRED 31 AUGUST 2026 !!
-- ============================================================================
--
-- The project owner deliberately KEPT the existing test accounts so they can be
-- used to exercise fake registrations, the OTP flow, and UI/UX validation, and
-- because the admin web panel still needs them to test document uploads and
-- document review.
--
-- Deleting them now would destroy the fixtures those tests depend on.
--
-- RUN THIS ONLY as part of the pre-beta checklist, immediately before the pilot
-- launch, once fake-registration and document-review testing is finished.
-- See .pipeline/PRE_BETA_CHECKLIST.md.
--
-- ============================================================================
-- READ THIS FIRST. DO NOT PASTE THE WHOLE FILE AND RUN IT.
-- ============================================================================
--
-- This file is in three parts and they are meant to be run SEPARATELY, in
-- order, with you reading the output between them:
--
--   PART 1  read-only. Shows you every account and what it is attached to.
--   PART 2  read-only. Shows exactly which accounts PART 3 would delete.
--   PART 3  DESTRUCTIVE. Only run it after PART 2 shows the list you expect.
--
-- Deleting an auth user cascades to public.profiles. It does NOT cascade to
-- trips, trip_events, driver_profiles, driver_availability, sos_reports, or the
-- other 12 tables that reference profiles(id) with a plain foreign key. An
-- account that has ever booked or driven a trip will therefore REFUSE to
-- delete, with a foreign-key violation, until its dependent rows are removed.
-- That refusal is a safety feature, not a bug -- it is stopping you from
-- silently destroying trip history. PART 3 handles it explicitly.
--
-- SAFETY.md section 9 requires explicit approval before deleting auth users in
-- bulk. That approval is you, reading PART 2, and choosing to run PART 3.

-- ============================================================================
-- PART 1 — What is actually in the project? (read-only)
-- ============================================================================

select
  u.id,
  u.email,
  u.phone,
  u.created_at,
  u.email_confirmed_at,
  u.phone_confirmed_at,
  u.last_sign_in_at,
  p.role,
  p.display_name,
  p.status,
  -- What would block a delete:
  (select count(*) from public.trips           t where t.rider_id  = u.id) as trips_as_rider,
  (select count(*) from public.trips           t where t.driver_id = u.id) as trips_as_driver,
  (select count(*) from public.driver_profiles d where d.id        = u.id) as driver_profile,
  (select count(*) from public.sos_reports     s where s.rider_id  = u.id) as sos_reports
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;

-- ============================================================================
-- PART 2 — Which accounts would be deleted? (read-only)
-- ============================================================================
--
-- KEEP LIST. Edit this and only this. Everything not listed here is deleted.
-- Add any account you want to survive — including any TODA or LGU admin
-- account you have already set up, which is easy to forget.

with keep as (
  select unnest(array[
    'tester@example.test'          -- the project owner's real account
    -- , 'add.another@example.com'  -- uncomment and edit to preserve more
  ]) as email
)
select
  u.id,
  u.email,
  p.role,
  p.display_name,
  u.created_at,
  case
    when u.email ilike '%@arangcada.demo' then 'demo/QA account'
    else 'test account'
  end as classification
from auth.users u
left join public.profiles p on p.id = u.id
where lower(u.email) not in (select lower(email) from keep)
order by u.created_at;

-- STOP. Read the list above. Does it contain anything you want to keep?
-- If yes, add it to the keep list and re-run PART 2 before continuing.

-- ============================================================================
-- PART 3 — DESTRUCTIVE. Delete everything not in the keep list.
-- ============================================================================
--
-- Wrapped in an explicit transaction. It ends with ROLLBACK so that running it
-- as-is changes NOTHING and simply proves it would succeed. When the output
-- looks right, change the last line to COMMIT and run it again.

begin;

create temporary table _doomed on commit drop as
with keep as (
  select unnest(array[
    'tester@example.test'
  ]) as email
)
select u.id
from auth.users u
where lower(u.email) not in (select lower(email) from keep);

-- Dependent rows first, in foreign-key order. Trip history for a deleted test
-- account is test data by definition, so it goes with the account.
delete from public.trip_events            where actor_id  in (select id from _doomed);
delete from public.trip_messages          where sender_id in (select id from _doomed);
delete from public.sos_reports            where rider_id  in (select id from _doomed);
delete from public.trips                  where rider_id  in (select id from _doomed)
                                             or driver_id in (select id from _doomed);
delete from public.driver_availability    where driver_id in (select id from _doomed);
delete from public.driver_documents       where driver_id in (select id from _doomed);
delete from public.driver_app_feedback    where driver_id in (select id from _doomed);
delete from public.driver_profiles        where id        in (select id from _doomed);
delete from public.push_tokens            where user_id   in (select id from _doomed);
delete from public.admin_audit_logs       where actor_id  in (select id from _doomed);

-- profiles cascades from auth.users, so deleting the user is enough.
delete from auth.users where id in (select id from _doomed);

-- Confirm what survived.
select u.email, p.role, p.display_name, p.status
from auth.users u left join public.profiles p on p.id = u.id
order by u.created_at;

-- Change to COMMIT when the output above is exactly what you want.
rollback;

-- ============================================================================
-- Notes
-- ============================================================================
--
-- * Some DELETE statements above may error with "relation does not exist" if a
--   table was never created in this project. That is fine -- remove that line
--   and re-run. It is safer to list a table that might not exist than to omit
--   one that does and hit a foreign-key wall mid-cleanup.
--
-- * admin_audit_logs is deliberately included, but think before running it: if
--   you have a real audit trail of admin actions you want to keep for the
--   paper, preserve those rows and delete the account reference instead.
--
-- * After cleanup, the surviving account will still be email-confirmed but NOT
--   phone-verified, because phone verification does not exist yet. See
--   .pipeline/spec-phone-otp-registration.md for how existing accounts are
--   handled when it lands.
