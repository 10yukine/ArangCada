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

create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set phone_verified_at = new.phone_confirmed_at,
         -- coalesce, not a bare assignment: new.phone can be null (an account
         -- that has never set a number at all), and profiles.phone is
         -- not-null + unique. Never overwrite a real number with null.
         phone = coalesce(new.phone, phone)
   where id = new.id
     and (
       phone_verified_at is distinct from new.phone_confirmed_at
       or phone is distinct from coalesce(new.phone, phone)
     );
  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors auth.users.phone_confirmed_at and auth.users.phone into '
  'profiles.phone_verified_at and profiles.phone. Never writes null over an '
  'existing number.';

drop trigger if exists on_auth_user_phone_confirmed on auth.users;
create trigger on_auth_user_phone_confirmed
  after insert or update of phone_confirmed_at, phone on auth.users
  for each row execute function public.sync_profile_phone_verified();

-- Back-fill anything already out of sync. On a fresh project, or one where no
-- number has ever changed post-signup, this is a no-op.
update public.profiles p
   set phone = u.phone
  from auth.users u
 where u.id = p.id
   and u.phone is not null
   and u.phone is distinct from p.phone;
