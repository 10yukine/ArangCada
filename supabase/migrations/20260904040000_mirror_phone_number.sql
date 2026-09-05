-- Mirror auth.users.phone into profiles.phone, alongside the timestamp.
--
-- WHY THIS EXISTS
--
-- 20260831130000_phone_verification.sql mirrors
-- auth.users.phone_confirmed_at into profiles.phone_verified_at, but nothing
-- mirrors the number itself. profiles.phone is written once by
-- handle_new_user() at signup and never touched again by a trigger. Spec 11
-- (§2, "Mobile number change") adds a client flow that changes an
-- already-verified account's number via `updateUser(phone:)` +
-- `verifyOTP(type: phoneChange)` -- after a successful change,
-- auth.users.phone is the new number but profiles.phone is still the old
-- one. profiles is what admin screens and driver records read (CLAUDE.md
-- "Suggested Core Tables"), so an admin would see a stale number after every
-- change.
--
-- WHY IT IS SAFE TO PIGGYBACK ON THE EXISTING TRIGGER
--
-- GoTrue keeps the confirmed number in auth.users.phone and parks the
-- claimed one in new_phone until the code is accepted -- proved on 4 Sep
-- 2026 when the SMS hook read `phone`, found it null during registration,
-- and rejected its own payload. So `phone` and `phone_confirmed_at` change
-- together, atomically, exactly at confirmation. The trigger that already
-- fires on `phone_confirmed_at` is therefore also fires whenever `phone`
-- meaningfully changes; this migration only widens its column list and its
-- function body to mirror both, not its firing condition's intent.
--
-- COUNCIL REVIEW REQUIRED -- this is an auth-adjacent trigger (touches
-- auth.users), and per .pipeline/specs.md Spec 11 §2 and CLAUDE.md's Council
-- Review Rule it must not be treated as load-bearing until reviewed. See
-- .pipeline/CURRENT_STATE.md.

--
-- GOTRUE OMITS THE "+"; profiles REQUIRES IT
--
-- The first version of this migration mirrored auth.users.phone verbatim and
-- the deploy refused it:
--
--   ERROR: new row for relation "profiles" violates check constraint
--          "profiles_phone_e164" (SQLSTATE 23514)
--   Failing row contains (..., 639170009945, ...)
--
-- GoTrue stores the number WITHOUT a leading "+"; profiles_phone_e164
-- (20260825120000) requires '^\+639[0-9]{9}$'. The two had disagreed since
-- August -- nothing mirrored the column before, so nothing had ever compared
-- them. The failed back-fill was the visible half and the harmless one: the
-- TRIGGER wrote the same unnormalised value, and it runs inside GoTrue's own
-- transaction, so every phone confirmation would have raised 23514 and
-- aborted the confirmation itself. That is registration broken for everyone.
--
-- It is corrected here, in place, rather than by a follow-up migration,
-- because this one had never been applied to any environment -- it failed on
-- first deploy. A later migration cannot fix it: ordering means this file
-- fails first and the fix never runs.
--
-- A value that cannot be normalised is SKIPPED, never raised. A stale
-- profiles row is recoverable; an aborted confirmation is not.

create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
begin
  -- Restore the "+" GoTrue omits, then accept the result ONLY if it is a
  -- well-formed PH mobile number. Anything else -- null (an account that has
  -- never set a number), a landline, a foreign number, junk -- leaves the
  -- stored value alone. profiles.phone is not-null and unique; never
  -- overwrite a real number with null or with something invalid.
  v_phone := nullif(btrim(coalesce(new.phone, '')), '');
  if v_phone is not null and left(v_phone, 1) <> '+' then
    v_phone := '+' || v_phone;
  end if;
  if v_phone !~ '^\+639[0-9]{9}$' then
    v_phone := null;
  end if;

  update public.profiles
     set phone_verified_at = new.phone_confirmed_at,
         phone = coalesce(v_phone, phone)
   where id = new.id
     and (
       phone_verified_at is distinct from new.phone_confirmed_at
       or phone is distinct from coalesce(v_phone, phone)
     );
  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors auth.users.phone_confirmed_at and auth.users.phone into '
  'profiles.phone_verified_at and profiles.phone. Restores the leading "+" '
  'that GoTrue omits. Skips the mirror rather than raising when the number is '
  'not a valid PH mobile, because raising would abort the phone confirmation.';

drop trigger if exists on_auth_user_phone_confirmed on auth.users;
create trigger on_auth_user_phone_confirmed
  after insert or update of phone_confirmed_at, phone on auth.users
  for each row execute function public.sync_profile_phone_verified();

-- Back-fill anything already out of sync. On a fresh project, or one where no
-- number has ever changed post-signup, this is a no-op.
update public.profiles p
   set phone = '+' || ltrim(btrim(u.phone), '+')
  from auth.users u
 where u.id = p.id
   and u.phone is not null
   and btrim(u.phone) <> ''
   and '+' || ltrim(btrim(u.phone), '+') ~ '^\+639[0-9]{9}$'
   and '+' || ltrim(btrim(u.phone), '+') is distinct from p.phone
   -- Never collide with a number another account already holds
   -- (profiles_phone_key is unique); leave those for a human.
   and not exists (
     select 1 from public.profiles other
      where other.phone = '+' || ltrim(btrim(u.phone), '+')
        and other.id <> p.id
   );
