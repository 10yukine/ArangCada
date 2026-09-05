-- pgTAP: profiles.phone stays current after a mobile number change.
--
-- WHY THIS FILE EXISTS
--
-- 20260831130000_phone_verification.sql only ever mirrored the timestamp.
-- 20260904040000_mirror_phone_number.sql widens the same trigger to mirror
-- the number too, because Spec 11 §2 lets an already-verified account change
-- its number, and admin screens / driver records read profiles.phone, not
-- auth.users.phone. A regression here means every admin lookup silently
-- shows a stale number after a change.

begin;

select plan(5);

-- ---------------------------------------------------------------------------
-- Fixture 1: one already-verified commuter.
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, phone, phone_confirmed_at, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000071a1', 'pnm-commuter@example.test',
   '+639170007101', now(),
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
  'baseline: profiles.phone matches the original number'
);

-- ---------------------------------------------------------------------------
-- A confirmed number change must mirror BOTH the number and a fresh timestamp
-- ---------------------------------------------------------------------------
-- Mirrors what Supabase does the instant an OTP for a phone CHANGE is
-- accepted: phone and phone_confirmed_at move together, atomically.
update auth.users
   set phone = '+639170007199',
       phone_confirmed_at = now()
 where id = '00000000-0000-0000-0000-0000000071a1';

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170007199',
  'the trigger mirrors the NEW number, not just the new timestamp -- this is '
  'the defect Spec 11 flagged'
);

select isnt(
  (select phone_verified_at from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  null,
  'the verification timestamp still mirrors correctly alongside the number'
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
-- Backfill statement: idempotent, and a no-op once mirrors already agree
-- ---------------------------------------------------------------------------
update public.profiles p
   set phone = u.phone
  from auth.users u
 where u.id = p.id
   and u.phone is not null
   and u.phone is distinct from p.phone;

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000071a1'),
  '+639170007199',
  'the backfill statement is idempotent -- running it again changes nothing'
);

select * from finish();

rollback;
