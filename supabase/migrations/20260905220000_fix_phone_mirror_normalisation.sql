-- Fix: auth.users.phone has no leading '+', profiles.phone requires one.
--
-- WHAT BROKE
--
-- 20260904040000 mirrored auth.users.phone into profiles.phone verbatim. It
-- was merged, and the Supabase deploy refused it:
--
--   ERROR: new row for relation "profiles" violates check constraint
--          "profiles_phone_e164" (SQLSTATE 23514)
--   Failing row contains (..., 639170009945, ...)
--
-- GoTrue stores the number WITHOUT the '+' ("639170009945"), while
-- profiles_phone_e164 (20260825120000) requires '^\+639[0-9]{9}$'. The two
-- have always disagreed; nothing mirrored the column before, so nothing had
-- ever compared them.
--
-- The failed back-fill was the visible half and the harmless one. The same
-- unnormalised value is written by the TRIGGER, so every phone confirmation
-- would have raised 23514 and aborted the update to auth.users -- breaking
-- registration for everyone, not just number changes.
--
-- WHY THE TESTS DID NOT CATCH IT
--
-- 71_phone_number_mirror_test.sql inserted '+639170007199' into
-- auth.users.phone. Real GoTrue never writes that shape. 371 assertions
-- passed against a fixture that could not occur in production. The fixture is
-- corrected in the same commit as this migration.
--
-- WHY IT SKIPS RATHER THAN RAISES
--
-- This trigger runs inside GoTrue's own transaction. Raising here does not
-- just fail the mirror, it fails the phone confirmation that triggered it. A
-- profiles row lagging behind is a stale admin display; a throw is a user who
-- cannot verify their number at all. So a value that cannot be normalised
-- into E.164 leaves profiles.phone untouched, and the trigger's original
-- promise -- never overwrite a real number with something worse -- is what
-- decides, not the caller's input.

create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
begin
  -- GoTrue omits the '+'; profiles requires it. Add it back, then accept the
  -- result ONLY if it is a well-formed PH mobile number. Anything else
  -- (null, a landline, a foreign number, junk) leaves the stored value alone.
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
  'GoTrue omits. Skips the mirror rather than raising when the number is not '
  'a valid PH mobile, because raising would abort the phone confirmation.';

-- Trigger definition is unchanged from 20260904040000; restated so this file
-- stands alone if the earlier one is ever squashed away.
drop trigger if exists on_auth_user_phone_confirmed on auth.users;
create trigger on_auth_user_phone_confirmed
  after insert or update of phone_confirmed_at, phone on auth.users
  for each row execute function public.sync_profile_phone_verified();

-- Re-run the back-fill that failed, now normalised and filtered. Rows whose
-- auth.users.phone cannot be made valid are skipped, not guessed at.
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
