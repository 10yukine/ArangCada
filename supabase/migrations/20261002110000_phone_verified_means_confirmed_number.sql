-- "Verified" must mean profiles.phone is the number auth.users confirmed
-- (release audit follow-up, 2 Oct 2026).
--
-- sync_profile_phone_verified() copied the confirmation time even when it
-- could not write the confirmed number: a number that is not a PH mobile, or
-- a PH number stored as 09XXXXXXXXX, which the '+' || phone rule turned into
-- something the E.164 check refused. The profile then read as verified while
-- profiles.phone still held whatever was typed at signup, which nobody had
-- proved. Drivers are shown profiles.phone as the rider's contact.
--
-- The app's own path cannot produce this today: the Send SMS hook only sends
-- a code to +639XXXXXXXXX / 639XXXXXXXXX. It is closed here anyway, so that a
-- number confirmed by any other route (dashboard, admin API, a changed hook)
-- cannot leave a profile verified for a different number.
--
-- Now:
--   * the confirmed number is normalized with normalize_ph_mobile(), so a
--     local-format PH number is mirrored instead of skipped;
--   * a number is mirrored only once it is confirmed;
--   * if there is no confirmed PH mobile to mirror, the profile is not
--     verified.
--
-- Regression: supabase/tests/71_phone_number_mirror_test.sql.
create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.normalize_ph_mobile(new.phone);
begin
  if new.phone_confirmed_at is null or v_phone is null then
    update public.profiles
       set phone_verified_at = null
     where id = new.id
       and phone_verified_at is not null;
    return new;
  end if;

  begin
    update public.profiles
       set phone_verified_at = new.phone_confirmed_at,
           phone = v_phone
     where id = new.id
       and (
         phone_verified_at is distinct from new.phone_confirmed_at
         or phone is distinct from v_phone
       );
  exception
    when unique_violation then
      -- Another verified profile holds the number. Raising here would abort
      -- the confirmation in auth.users and show the user "wrong code".
      update public.profiles
         set phone_verified_at = null
       where id = new.id
         and phone_verified_at is not null;
  end;

  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors a confirmed auth.users.phone into profiles.phone and '
  'profiles.phone_verified_at. A profile is verified only for the number '
  'that was confirmed: with no confirmed PH mobile, or when another verified '
  'profile already holds it, the profile is left unverified.';

-- Rows the earlier versions may have left behind. Nothing is skipped quietly:
-- each case is counted and reported.
do $$
declare
  v_corrected integer;
  v_unverified integer;
  v_unbacked integer;
begin
  -- Verified for a different number than the confirmed one: write the
  -- confirmed number, unless another verified profile holds it.
  with corrected as (
    update public.profiles p
       set phone = public.normalize_ph_mobile(u.phone)
      from auth.users u
     where u.id = p.id
       and p.phone_verified_at is not null
       and u.phone_confirmed_at is not null
       and public.normalize_ph_mobile(u.phone) is not null
       and public.normalize_ph_mobile(u.phone) is distinct from p.phone
       and not exists (
         select 1 from public.profiles other
          where other.id <> p.id
            and other.phone = public.normalize_ph_mobile(u.phone)
            and other.phone_verified_at is not null
       )
    returning 1
  )
  select count(*) into v_corrected from corrected;

  -- Still not matching a confirmed PH mobile: not verified.
  with unverified as (
    update public.profiles p
       set phone_verified_at = null
      from auth.users u
     where u.id = p.id
       and p.phone_verified_at is not null
       and u.phone_confirmed_at is not null
       and public.normalize_ph_mobile(u.phone) is distinct from p.phone
    returning 1
  )
  select count(*) into v_unverified from unverified;

  -- Marked verified with nothing confirmed in auth.users at all. Left as they
  -- are (that is how a number is marked by hand), but reported.
  select count(*) into v_unbacked
    from public.profiles p
    join auth.users u on u.id = p.id
   where p.phone_verified_at is not null
     and u.phone_confirmed_at is null;

  raise notice 'phone reconciliation: % corrected to the confirmed number, % set unverified, % verified with no confirmation in auth.users (unchanged)',
    v_corrected, v_unverified, v_unbacked;
end;
$$;
