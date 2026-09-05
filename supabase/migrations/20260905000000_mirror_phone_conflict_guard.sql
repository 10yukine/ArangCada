-- sync_profile_phone_verified() can raise unique_violation and abort a
-- legitimate OTP verification, misreporting it to the user as "wrong code".
--
-- HOW THIS HAPPENS
--
-- profiles.phone is UNIQUE (profiles_phone_key,
-- 20260825120000_profiles_identity_columns.sql). handle_new_user() writes
-- profiles.phone from signup metadata at INSERT time, before the number is
-- verified -- auth.users.phone stays null until that account's own OTP is
-- accepted. Such an account can sit unverified for up to two hours before
-- sweep_abandoned_registrations() removes it, and indefinitely for an
-- internal tester (is_internal_tester short-circuits the sweep).
--
-- If a second, real user then completes a phone-number CHANGE to that exact
-- number, GoTrue confirms it in auth.users first and this trigger fires
-- inside that same transaction. The UPDATE at line ~81 of
-- 20260904040000_mirror_phone_number.sql tries to write the now-verified
-- number into profiles.phone for the second user, collides with the first
-- user's still-parked row, and PostgreSQL raises unique_violation --
-- rolling back the entire OTP-verify transaction. The number WAS correct;
-- the user sees "incorrect or expired" and has no way to tell why.
--
-- THE FIX
--
-- A stale, unverified profiles.phone is exactly the kind of value this
-- trigger already treats as skippable (see the invalid-format branch it
-- widened around). Catching unique_violation and leaving the row alone is
-- consistent with that: the mirror is best-effort, and skipping it here
-- never blocks the auth.users confirmation that matters. The stale row gets
-- cleaned up by sweep_abandoned_registrations() (or a human, for a tester)
-- exactly as it would have anyway; nothing about this fix removes that
-- cleanup path.
--
-- COUNCIL REVIEW REQUIRED -- same auth-adjacent trigger as
-- 20260904040000_mirror_phone_number.sql; queued alongside it in
-- .pipeline/CURRENT_STATE.md.

create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
begin
  v_phone := nullif(btrim(coalesce(new.phone, '')), '');
  if v_phone is not null and left(v_phone, 1) <> '+' then
    v_phone := '+' || v_phone;
  end if;
  if v_phone !~ '^\+639[0-9]{9}$' then
    v_phone := null;
  end if;

  begin
    update public.profiles
       set phone_verified_at = new.phone_confirmed_at,
           phone = coalesce(v_phone, phone)
     where id = new.id
       and (
         phone_verified_at is distinct from new.phone_confirmed_at
         or phone is distinct from coalesce(v_phone, phone)
       );
  exception
    when unique_violation then
      -- Another (almost certainly stale/unverified) profiles row already
      -- holds this number. Mirror only the confirmation timestamp instead of
      -- letting the whole trigger -- and the auth.users transaction it runs
      -- inside -- fail. The number itself stays out of sync until that other
      -- row is cleared, which is no worse than before this trigger mirrored
      -- the number at all.
      update public.profiles
         set phone_verified_at = new.phone_confirmed_at
       where id = new.id
         and phone_verified_at is distinct from new.phone_confirmed_at;
  end;

  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors auth.users.phone_confirmed_at and auth.users.phone into '
  'profiles.phone_verified_at and profiles.phone. Restores the leading "+" '
  'that GoTrue omits. Skips the phone mirror (but still records verification '
  'time) rather than raising, both when the number is not a valid PH mobile '
  'and when it collides with another profiles row -- raising here would abort '
  'the phone confirmation itself.';
