-- Create a profiles row whenever an auth user is created.
--
-- WHY THIS EXISTS
--
-- Until this migration, nothing ever created a public.profiles row. The
-- client writes display_name and mobile_number into Supabase Auth *user
-- metadata* (apps/mobile/lib/data/remote/supabase_auth_repository.dart), and
-- no trigger copied them anywhere. public.profiles was therefore empty for
-- every real account, which meant:
--
--   * is_admin() could never return true -- there was no row to hold
--     role = 'admin' -- so every admin RLS policy written in 2eef1c7 was
--     unreachable in practice;
--   * the driver onboarding lookups would resolve nobody, because there was
--     nobody to resolve.
--
-- Found during spec self-review, not by a failing feature, because the app
-- has been running on local demo auth where the gap does not show.
--
-- WHY IT RAISES INSTEAD OF DEFAULTING
--
-- A profile with an invented placeholder phone number would be worse than no
-- profile: it would satisfy the unique constraint, look valid to an admin
-- doing a lookup, and quietly represent a person who cannot actually be
-- contacted. Failing the signup outright puts the error where someone can
-- still fix it -- at the client that omitted the field.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name text;
  v_phone        text;
begin
  v_display_name := nullif(trim(new.raw_user_meta_data ->> 'display_name'), '');
  v_phone        := public.normalize_ph_mobile(new.raw_user_meta_data ->> 'mobile_number');

  if v_display_name is null then
    raise exception 'handle_new_user: display_name missing from user metadata for auth user %', new.id
      using errcode = '23502',
            hint    = 'Pass display_name in the signUp/createUser user metadata.';
  end if;

  if v_phone is null then
    -- Deliberately does not echo the offending value (no personal data in logs)
    -- keeps phone numbers out of logs, and an exception message is a log.
    raise exception 'handle_new_user: mobile_number missing or not a valid PH mobile number for auth user %', new.id
      using errcode = '23514',
            hint    = 'Pass mobile_number in user metadata as 09XXXXXXXXX or +639XXXXXXXXX.';
  end if;

  if new.email is null then
    raise exception 'handle_new_user: auth user % has no email address', new.id
      using errcode = '23502',
            hint    = 'ArangCada resolves accounts by email during driver onboarding, so an email is required.';
  end if;

  -- on conflict do nothing keeps this idempotent. A profile row may already
  -- exist when an administrative path creates one explicitly; re-running must
  -- not clobber it or fail the signup.
  insert into public.profiles (id, display_name, phone, email)
  values (new.id, v_display_name, v_phone, lower(new.email))
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Creates the public.profiles row for a new auth user, reading display_name '
  'and mobile_number from user metadata and normalising the number to E.164. '
  'Raises rather than inventing placeholder identity values.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Keep the denormalised email current
-- ---------------------------------------------------------------------------
-- profiles.email is a copy, and a stale copy is worse than no copy here: the
-- onboarding duplicate check resolves people by email, so an out-of-date
-- value could let a genuine duplicate through as "no existing account".
create or replace function public.sync_profile_email()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is not null and new.email is distinct from old.email then
    update public.profiles
       set email      = lower(new.email),
           updated_at = now()
     where id = new.id;
  end if;
  return new;
end;
$$;

comment on function public.sync_profile_email() is
  'Mirrors an auth.users email change onto profiles.email, so the onboarding '
  'duplicate check never resolves against a stale address.';

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  execute function public.sync_profile_email();
