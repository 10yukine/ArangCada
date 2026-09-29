-- Fix: the invited-admin phone exemption never actually worked.
--
-- Summary: 20260908020000 gated the exemption on
-- `new.raw_app_meta_data ->> 'invited_admin'`, reasoning that app_metadata
-- can only be set through the Auth Admin API and is therefore unspoofable
-- by a client's own signUp() call.
--
-- That reasoning was correct about WHO can set app_metadata, but wrong
-- about WHEN it becomes visible. Live verification against the hosted
-- project (Auth service logs, then a temporary non-raising diagnostic
-- trigger that captured what handle_new_user() actually observed) proved
-- that GoTrue's admin.createUser() writes the auth.users row with only
-- its own default app_metadata (provider/providers) first, and merges in
-- the caller-supplied app_metadata as a separate follow-up step -- by
-- which point this AFTER INSERT trigger has already fired and, finding no
-- invited_admin key yet, already raised. raw_user_meta_data (display_name)
-- does not have this problem -- it is present on the very first insert,
-- confirmed by the same diagnostic.
--
-- WHY MOVING TO raw_user_meta_data IS SAFE, NOT A REGRESSION
--
-- The concern that motivated app_metadata in the first place was that a
-- malicious client could spoof user_metadata (it already can -- that is
-- the whole reason app_metadata exists). But this flag was never the
-- security boundary for admin escalation to begin with: profiles.role
-- stays 'commuter' by default for every new signup, admin invite or not.
-- The ONLY place role ever becomes 'admin' is
-- admin_finalize_invited_account(), which is service_role-only and gated
-- entirely by the invite's own hashed, single-use, LGU-issued token --
-- never by this flag. Spoofing 'invited_admin' on an ordinary signUp()
-- call cannot grant admin access; the worst it can do is let a commuter
-- register without a phone number, and phone_verified_at (required
-- elsewhere for booking) can then never be set for that account -- a
-- useless account, not a privilege escalation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_display_name   text;
  v_phone          text;
  v_invited_admin  boolean;
begin
  v_display_name  := nullif(trim(new.raw_user_meta_data ->> 'display_name'), '');
  v_phone         := public.normalize_ph_mobile(new.raw_user_meta_data ->> 'mobile_number');
  v_invited_admin := coalesce(new.raw_user_meta_data ->> 'invited_admin', 'false') = 'true';

  if v_display_name is null then
    raise exception 'handle_new_user: display_name missing from user metadata for auth user %', new.id
      using errcode = '23502',
            hint    = 'Pass display_name in the signUp/createUser user metadata.';
  end if;

  -- Admin accounts created through the invite flow are exempt:
  -- they never book a ride or receive a dispatch call, so there is no
  -- contactability requirement the way there is for a commuter or driver.
  if v_phone is null and not v_invited_admin then
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
  'Creates the public.profiles row for a new auth user, reading display_name, '
  'mobile_number, and invited_admin from raw_user_meta_data -- all three are '
  'confirmed present at insert time, unlike raw_app_meta_data (see this '
  'migration''s header). Raises rather than inventing placeholder identity '
  'values, except for an invited admin account, which has no '
  'phone requirement at all.';
