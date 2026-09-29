-- pgTAP: profiles.phone stays current after a mobile number change.
--
-- WHY THIS FILE EXISTS
--
-- 20260831130000_phone_verification.sql only ever mirrored the timestamp.
-- 20260904040000_mirror_phone_number.sql widens the same trigger to mirror
-- the number too, because an already-verified account can change
-- its number, and admin screens / driver records read profiles.phone, not
-- auth.users.phone. A regression here means every admin lookup silently
-- shows a stale number after a change.
--
-- FIXTURE SHAPE MATTERS HERE, AND THIS FILE ORIGINALLY GOT IT WRONG.
--
-- The first version inserted '+639170007101' into auth.users.phone. GoTrue
-- never writes that shape: it stores the number WITHOUT the leading '+'
-- ("639170007101"), while profiles_phone_e164 requires one. Five assertions
-- passed against a value production cannot produce, and the deploy of
-- 20260904040000 then failed on real data with SQLSTATE 23514. Every
-- auth.users.phone below is unprefixed on purpose. Do not "fix" them by
-- adding a '+' -- that is the bug, not a typo.

begin;

select plan(11);

-- ---------------------------------------------------------------------------
-- REGRESSION: Security Advisor "Public Can Execute SECURITY DEFINER
-- Function" on this trigger function. Fixed by
-- 20260905010000_advisor_sync_phone_trigger_grants.sql. No grant to
-- authenticated either -- nothing should call a trigger function directly,
-- and Postgres refuses it outright regardless of privilege.
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('public', 'public.sync_profile_phone_verified()', 'execute'),
  'sync_profile_phone_verified() is not executable by public'
);

select ok(
  not has_function_privilege('anon', 'public.sync_profile_phone_verified()', 'execute'),
  'sync_profile_phone_verified() is not executable by anon'
);

-- ---------------------------------------------------------------------------
-- Fixture 1: one already-verified commuter.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000071a1', 'pnm-commuter@example.test',
   '639170007101', now(),
   '{"display_name":"PNM Commuter","mobile_number":"+639170007101"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status, phone_verified_at) values
  ('00000000-0000-0000-0000-0000000071a1', 'commuter', 'PNM Commuter',
   '+639170007101', 'pnm-commuter@example.test', 'active', now())
on conflict (id) do update
  set phone = excluded.phone, phone_verified_at = excluded.phone_verified_at;

-- ---------------------------------------------------------------------------
-- Baseline: the mirror already agrees with the fixture.
-- ---------------------------------------------------------------------------
select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170007101',
  'baseline: profiles.phone keeps E.164 even though auth.users has no "+"'
);

-- ---------------------------------------------------------------------------
-- A confirmed number change must mirror BOTH the number and a fresh timestamp
-- ---------------------------------------------------------------------------
-- Mirrors what Supabase does the instant an OTP for a phone CHANGE is
-- accepted: phone and phone_confirmed_at move together, atomically.
update auth.users
   set phone = '639170007199',
       phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000071a1';

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170007199',
  'the trigger mirrors the NEW number and restores the "+" GoTrue omits'
);

select isnt(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  null,
  'the verification timestamp still mirrors correctly alongside the number'
);

-- ---------------------------------------------------------------------------
-- REGRESSION: the exact value that failed the 5 Sep 2026 deploy.
-- An unprefixed number must not raise 23514. This trigger runs inside
-- GoTrue's own transaction, so a throw here aborts the phone confirmation
-- itself and breaks registration -- not merely the mirror.
-- ---------------------------------------------------------------------------
select lives_ok(
  $q$update auth.users set phone = '639170009945', phone_confirmed_at = now()
      where id = '00000000-0000-0000-0000-0000000071a1'$q$,
  'an unprefixed GoTrue number does not violate profiles_phone_e164'
);

-- ---------------------------------------------------------------------------
-- A number that cannot be normalised is SKIPPED: never written, never raised.
-- A stale profiles row is recoverable; an aborted confirmation is not.
-- ---------------------------------------------------------------------------
update auth.users set phone = '12025550123', phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000071a1';

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170009945',
  'a non-PH number leaves the last good number in place rather than raising'
);

-- ---------------------------------------------------------------------------
-- Fixture 2: a brand-new signup, the way registration actually inserts one --
-- auth.users.phone and phone_confirmed_at both start null; the number lives
-- only in raw_user_meta_data until the SMS code is later accepted. This is
-- the real-world case for the trigger's null-guard: BOTH the insert trigger
-- that creates the profiles row (handle_new_user) and this one fire on the
-- same INSERT, in an order this migration must not depend on.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000071a2', 'pnm-fresh@example.test',
   '{"display_name":"PNM Fresh","mobile_number":"+639170007102"}'::jsonb);

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a2'),
  '+639170007102',
  'a null auth.users.phone at insert never blanks out the real number '
  'handle_new_user() just wrote from signup metadata'
);

-- ---------------------------------------------------------------------------
-- REGRESSION: a phone collision must not abort the confirming user's OTP
-- transaction. A third, unverified account (handle_new_user() writes
-- profiles.phone from signup metadata before the number is ever confirmed --
-- see 20260905000000_mirror_phone_conflict_guard.sql) is already sitting on
-- the number that fixture 1 is about to confirm. profiles.phone is UNIQUE,
-- so the mirror's UPDATE collides. Before the conflict guard this raised
-- unique_violation and rolled back the whole trigger transaction -- the same
-- class of failure as the unprefixed-number regression above, just from a
-- different cause.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000071a3', 'pnm-stale@example.test',
   '{"display_name":"PNM Stale","mobile_number":"+639170007103"}'::jsonb);

-- handle_new_user() already wrote this from signup metadata; assert the
-- fixture is what this test needs before relying on it.
select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a3'),
  '+639170007103',
  'fixture: the stale unverified account holds the number that will collide'
);

select lives_ok(
  $q$update auth.users set phone = '639170007103', phone_confirmed_at = now()
      where id = '00000000-0000-0000-0000-0000000071a1'$q$,
  'confirming a number another (unverified) profiles row already holds does '
  'not raise -- it must not abort the OTP-verify transaction'
);

-- ---------------------------------------------------------------------------
-- Backfill statement: idempotent, and a no-op once mirrors already agree
-- ---------------------------------------------------------------------------
update public.profiles p
   set phone = '+' || ltrim(btrim(u.phone), '+')
  from auth.users u
 where u.id = p.id
   and u.phone is not null
   and btrim(u.phone) <> ''
   and '+' || ltrim(btrim(u.phone), '+') ~ '^\+639[0-9]{9}$'
   and '+' || ltrim(btrim(u.phone), '+') is distinct from p.phone
   and not exists (
     select 1 from public.profiles other
      where other.phone = '+' || ltrim(btrim(u.phone), '+')
        and other.id <> p.id
   );

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170009945',
  'the backfill skips the unnormalisable number rather than corrupting the row'
);

select * from finish();

rollback;
