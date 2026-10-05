-- Email confirmation by a link, separate from the phone code.
--
-- Sign-up does not make Supabase Auth confirm the email (that would stop a new
-- user signing in before the phone step), so profiles.email is whatever was
-- typed. The only proof of the mailbox so far has been the one-time code, and
-- only because that code is emailed while there is no SMS sender name.
--
-- This adds the app's own confirmation. The send-email-confirmation Edge
-- Function emails a single-use link; confirm-email redeems it; and
-- profiles.email_confirmed_at records it. Nothing is refused for an
-- unconfirmed email yet: the app shows a prompt on the Profile screen.
--
-- Only those two functions (the service role) may create or redeem a link. A
-- signed-in user must never be able to mint one for themselves, or opening it
-- would prove nothing. Links are stored as a SHA-256 hash, never as sent.
--
-- Regression: supabase/tests/100_email_confirmation_test.sql

alter table public.profiles add column email_confirmed_at timestamptz;

comment on column public.profiles.email_confirmed_at is
  'When the account holder opened the confirmation link sent to profiles.email. '
  'Null again whenever the email changes. Written only by confirm_email().';

create table public.email_confirmations (
  token_hash text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  -- The address the link was sent to. A link confirms that address only.
  email      text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at    timestamptz
);

comment on table public.email_confirmations is
  'Single-use email confirmation links, hashed. Read and written only through '
  'create_email_confirmation() and confirm_email().';

create index email_confirmations_user_idx
  on public.email_confirmations (user_id, created_at desc);

alter table public.email_confirmations enable row level security;
revoke all on public.email_confirmations from public, anon, authenticated;

-- Changing the email takes the confirmation with it, whoever changes it
-- (sync_profile_email mirrors auth.users, so this covers the app's own
-- change-email screen).
create function public.clear_email_confirmation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.email is distinct from old.email then
    new.email_confirmed_at := null;
  end if;
  return new;
end;
$$;

revoke all on function public.clear_email_confirmation() from public, anon, authenticated;

create trigger profiles_email_change_clears_confirmation
  before update of email on public.profiles
  for each row execute function public.clear_email_confirmation();

-- Records a new link for an account and answers with the address to send it
-- to. Refusals the user can act on carry SQLSTATE 22023 and a sentence the
-- app shows as it is.
create function public.create_email_confirmation(p_user_id uuid, p_token_hash text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'a sha-256 token hash is required' using errcode = '22023';
  end if;

  select * into v_profile from public.profiles where id = p_user_id for update;
  if not found or v_profile.email is null then
    raise exception 'no such account' using errcode = 'P0002';
  end if;

  -- The link follows the number check, as sign-up does. It also means a link
  -- cannot be sent to a stranger's address from an account nobody verified.
  if not public.is_verified_account(p_user_id) then
    raise exception 'Verify your mobile number first.' using errcode = '22023';
  end if;

  if v_profile.email_confirmed_at is not null then
    raise exception 'This email is already confirmed.' using errcode = '22023';
  end if;

  -- One link a minute and five a day: room for a retry, not enough to fill
  -- the inbox of an address somebody mistyped.
  if exists (
    select 1 from public.email_confirmations
     where user_id = p_user_id and created_at > now() - interval '1 minute'
  ) then
    raise exception 'Please wait a minute before asking for another link.'
      using errcode = '22023';
  end if;
  if (
    select count(*) from public.email_confirmations
     where user_id = p_user_id and created_at > now() - interval '1 day'
  ) >= 5 then
    raise exception 'You have asked for the most links allowed today. Try again tomorrow.'
      using errcode = '22023';
  end if;

  -- ponytail: old links are cleared here instead of by a scheduled job.
  delete from public.email_confirmations where expires_at < now() - interval '1 day';

  insert into public.email_confirmations (token_hash, user_id, email, expires_at)
  values (p_token_hash, p_user_id, v_profile.email, now() + interval '24 hours');

  return v_profile.email;
end;
$$;

-- Redeems a link. True when it confirmed the account's current email; false
-- when the link is unknown, used, expired, or was sent to an address the
-- account no longer has.
create function public.confirm_email(p_token_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.email_confirmations%rowtype;
begin
  select * into v_link from public.email_confirmations
   where token_hash = p_token_hash
   for update;
  if not found or v_link.used_at is not null or v_link.expires_at <= now() then
    return false;
  end if;

  update public.email_confirmations set used_at = now()
   where token_hash = p_token_hash;

  update public.profiles
     set email_confirmed_at = now(), updated_at = now()
   where id = v_link.user_id and email = v_link.email;
  return found;
end;
$$;

revoke all on function public.create_email_confirmation(uuid, text) from public, anon, authenticated;
revoke all on function public.confirm_email(text) from public, anon, authenticated;
grant execute on function public.create_email_confirmation(uuid, text) to service_role;
grant execute on function public.confirm_email(text) to service_role;
