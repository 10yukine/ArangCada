-- LGU/TODA admin accounts: email invite, GUI, and self-serve account
-- creation.
--
-- Only an unscoped LGU admin (is_admin() = true -- a TODA-scoped admin's own
-- is_admin() is already false, see 20260825133421) may invite a new LGU or
-- TODA admin. The invited person never gets a password from anyone else:
-- they receive a one-time link, open it, and set their own password. The
-- real account is created only when they accept -- never at invite time.

-- ---------------------------------------------------------------------------
-- 1. profiles: first_name / last_name (admin-accounts-only this pass)
-- ---------------------------------------------------------------------------
-- Nullable, populated only by admin_finalize_invited_account() below.
-- display_name (already required by handle_new_user()) stays the single
-- source of truth for what the admin console rail/footer displays -- these
-- two columns exist only so the new Admins screen can render "First Last"
-- without re-splitting display_name. Not a privileged pair of columns the
-- way role/status are, so profiles_update_own already covers self-editing
-- them, same as display_name today.
alter table public.profiles
  add column first_name text,
  add column last_name  text;

-- profiles.phone has been NOT NULL since 20260825120000 -- correct for every
-- commuter and driver, both of which handle_new_user() already refuses to
-- create without one. An invited admin account is real and permanent but
-- never dispatched to or contacted the way a driver is, so it has nothing to
-- be reachable *for*. The E.164 check constraint and the unique index both
-- already tolerate null (a CHECK passes on null, and a unique index allows
-- any number of nulls), so only the NOT NULL needs to move.
alter table public.profiles
  alter column phone drop not null;

-- ---------------------------------------------------------------------------
-- 2. admin_invites
-- ---------------------------------------------------------------------------
create table public.admin_invites (
  id                uuid primary key default gen_random_uuid(),
  email             text not null,
  scope             text not null check (scope in ('lgu', 'toda')),
  toda_zone_id      uuid references public.toda_zones (id),
  invited_by        uuid not null references public.profiles (id),
  -- sha256(token)::hex, never the raw token. sha256(bytea) is core
  -- PostgreSQL (no pgcrypto extension-schema qualification needed under
  -- set search_path = ''), same reason ride_share_links (20260831120000)
  -- uses bare gen_random_uuid() instead of a pgcrypto random-bytes call.
  -- Deliberately hashed, unlike ride_share_links' plaintext token: that
  -- token grants five minutes of read-only trip tracking, this one grants
  -- creation of a brand-new administrator account.
  token_hash        text not null unique,
  status            text not null default 'pending'
                       check (status in ('pending', 'accepted', 'revoked')),
  created_at        timestamptz not null default now(),
  expires_at        timestamptz not null default (now() + interval '7 days'),
  accepted_at       timestamptz,
  accepted_user_id  uuid references public.profiles (id),
  constraint admin_invites_zone_matches_scope check (
    (scope = 'lgu'  and toda_zone_id is null)
    or (scope = 'toda' and toda_zone_id is not null)
  ),
  constraint admin_invites_token_hash_length check (char_length(token_hash) = 64)
);

create index admin_invites_email_idx on public.admin_invites (email);

comment on table public.admin_invites is
  'One-time-use LGU/TODA admin account invites. The raw token is returned '
  'once by admin_create_invite() and never stored -- only its sha256 hash '
  'is kept. ';

alter table public.admin_invites enable row level security;

create policy admin_invites_select_lgu
  on public.admin_invites for select
  using (public.is_admin(auth.uid()));

-- No insert/update/delete policy for anyone, admins included -- every write
-- goes through the security definer RPCs below, matching admin_audit_logs'
-- own established shape.

-- ---------------------------------------------------------------------------
-- 3. Creating an invite (LGU only)
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_invite(
  p_email        text,
  p_scope        text,
  p_toda_zone_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email     text := lower(trim(p_email));
  v_token     text;
  v_invite_id uuid;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can send an admin invite'
      using errcode = '42501';
  end if;

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'a valid email address is required'
      using errcode = '22023';
  end if;

  if p_scope not in ('lgu', 'toda') then
    raise exception 'scope must be lgu or toda'
      using errcode = '22023';
  end if;

  if p_scope = 'lgu' and p_toda_zone_id is not null then
    raise exception 'an lgu invite must not carry a toda zone'
      using errcode = '22023';
  end if;
  if p_scope = 'toda' and p_toda_zone_id is null then
    raise exception 'a toda invite requires a toda zone'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.profiles
     where email = v_email and role = 'admin' and status = 'active'
  ) then
    raise exception 'this email already belongs to an administrator account'
      using errcode = '23505';
  end if;

  -- A resend supersedes rather than piling up dead rows.
  update public.admin_invites
     set status = 'revoked'
   where email = v_email and status = 'pending';

  -- 64 hex characters from two gen_random_uuid() calls: ~244 bits of
  -- entropy, same construction ride_share_links.token uses.
  v_token := replace(gen_random_uuid()::text, '-', '')
          || replace(gen_random_uuid()::text, '-', '');

  insert into public.admin_invites (email, scope, toda_zone_id, invited_by, token_hash)
  values (v_email, p_scope, p_toda_zone_id, auth.uid(), encode(sha256(v_token::bytea), 'hex'))
  returning id into v_invite_id;

  insert into public.admin_audit_logs (actor_id, action, metadata)
  values (
    auth.uid(),
    'admin_invite.created',
    jsonb_build_object('invite_id', v_invite_id, 'scope', p_scope, 'toda_zone_id', p_toda_zone_id)
  );

  return v_token;
end;
$$;

comment on function public.admin_create_invite(text, text, uuid) is
  'LGU-only. Mints a one-time invite token (returned once, never stored) '
  'for a new LGU or TODA admin account.';

revoke execute on function public.admin_create_invite(text, text, uuid) from public, anon;
grant execute on function public.admin_create_invite(text, text, uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Revoking a pending invite (LGU only)
-- ---------------------------------------------------------------------------
create or replace function public.admin_revoke_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can revoke an admin invite'
      using errcode = '42501';
  end if;

  update public.admin_invites
     set status = 'revoked'
   where id = p_invite_id and status = 'pending';

  if found then
    insert into public.admin_audit_logs (actor_id, action, metadata)
    values (auth.uid(), 'admin_invite.revoked', jsonb_build_object('invite_id', p_invite_id));
  end if;
end;
$$;

comment on function public.admin_revoke_invite(uuid) is
  'LGU-only. Cancels a still-pending invite, e.g. a typo''d email.';

revoke execute on function public.admin_revoke_invite(uuid) from public, anon;
grant execute on function public.admin_revoke_invite(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Looking up an invite by token (public -- the recipient has no session)
-- ---------------------------------------------------------------------------
-- Same shape as ride_share_view() (20260831120000): a hand-picked column
-- list, zero rows for anything wrong without saying why. Called directly by
-- apps/admin_web's public accept page via the anon key -- no Edge Function
-- hop needed for this read.
create or replace function public.admin_invite_lookup(p_token text)
returns table (email text)
language sql
stable
security definer
set search_path = ''
as $$
  select i.email
    from public.admin_invites i
   where i.token_hash = encode(sha256(p_token::bytea), 'hex')
     and i.status = 'pending'
     and i.expires_at > now();
$$;

comment on function public.admin_invite_lookup(text) is
  'Anon-reachable. Resolves a pending, unexpired invite token to its locked '
  'email for the accept-invite form. Zero rows for any invalid token.';

revoke execute on function public.admin_invite_lookup(text) from public;
grant execute on function public.admin_invite_lookup(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 6. Finalizing an accepted invite (service_role only)
-- ---------------------------------------------------------------------------
-- Called by the accept-admin-invite Edge Function immediately after it
-- creates the auth user via the Auth Admin API. p_user_id is passed
-- explicitly because a service_role connection has no auth.uid() -- same
-- reasoning admin_activate_new_driver() (20260825120700) documents.
create or replace function public.admin_finalize_invited_account(
  p_invite_token text,
  p_user_id      uuid,
  p_first_name   text,
  p_last_name    text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.admin_invites%rowtype;
begin
  -- current_setting('role'), not current_user -- see admin_activate_new_driver
  -- (20260825120700) for why current_user is wrong inside a definer function.
  -- The GRANT below is the primary control; this is defence in depth.
  if coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'admin_finalize_invited_account: callable only by a trusted server process'
      using errcode = '42501';
  end if;

  select * into v_invite
    from public.admin_invites
   where token_hash = encode(sha256(p_invite_token::bytea), 'hex')
     and status = 'pending'
     and expires_at > now()
   for update;

  if not found then
    raise exception 'admin_finalize_invited_account: invite is no longer valid'
      using errcode = '42501';
  end if;

  update public.profiles
     set role       = 'admin',
         first_name = nullif(trim(p_first_name), ''),
         last_name  = nullif(trim(p_last_name), ''),
         updated_at = now()
   where id = p_user_id;

  if not found then
    raise exception 'admin_finalize_invited_account: no profile exists for %', p_user_id
      using errcode = 'P0002';
  end if;

  -- An lgu invite writes no admin_scopes row at all -- is_admin() already
  -- treats "admin, no scope row" as LGU (20260825133421). Only a toda
  -- invite adds one.
  if v_invite.scope = 'toda' then
    insert into public.admin_scopes (admin_id, scope, toda_zone_id)
    values (p_user_id, 'toda', v_invite.toda_zone_id);
  end if;

  update public.admin_invites
     set status           = 'accepted',
         accepted_at      = now(),
         accepted_user_id = p_user_id
   where id = v_invite.id;

  -- actor_id is the inviting LGU admin, not the anonymous accept request
  -- (which has no auth.uid() of its own) -- they are who authorized this
  -- account existing.
  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    v_invite.invited_by,
    'admin_invite.accepted',
    p_user_id,
    jsonb_build_object('invite_id', v_invite.id, 'scope', v_invite.scope)
  );
end;
$$;

comment on function public.admin_finalize_invited_account(text, uuid, text, text) is
  'service_role only. Promotes a freshly created auth user to admin (and to '
  'the invite''s TODA scope, if any) once the Edge Function has created the '
  'account via the Auth Admin API.';

revoke execute on function public.admin_finalize_invited_account(text, uuid, text, text)
  from anon, authenticated;
grant execute on function public.admin_finalize_invited_account(text, uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7. handle_new_user(): one new branch, phone exempt for invited admins
-- ---------------------------------------------------------------------------
-- raw_app_meta_data is set only via the Auth Admin API (service_role),
-- never by a client's own signUp() call -- that call's `data` payload
-- always becomes raw_user_meta_data, a different column GoTrue does not let
-- a client touch. A commuter or driver signing up through the mobile app
-- has no way to set this flag, so this cannot be used to dodge the phone
-- requirement outside the invite path. Full function body replaced (same
-- idiom this migration history already uses for is_admin() twice) because
-- plpgsql cannot gain a conditional branch via alter function.
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
  v_invited_admin := coalesce(new.raw_app_meta_data ->> 'invited_admin', 'false') = 'true';

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
  'Creates the public.profiles row for a new auth user, reading display_name '
  'and mobile_number from user metadata and normalising the number to E.164. '
  'Raises rather than inventing placeholder identity values, except for an '
  'invited admin account, which has no phone requirement at all.';
