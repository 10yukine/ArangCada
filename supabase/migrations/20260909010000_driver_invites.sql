-- Driver enrollment by email: LGU-initiated, mirrors the admin invite
-- system (Spec 19). See .pipeline/specs.md Spec 20.
--
-- The "email already has an account" case needs no new machinery at all --
-- admin_preview_driver_candidate() and admin_promote_commuter_to_driver()
-- (20260825120700) already do exactly that, LGU-only, and are reused here
-- unchanged, called directly from apps/admin_web with no Edge Function.
--
-- This migration is only for the "no account yet" case: an invite, email
-- sent, the driver fills in their own name/phone/password to accept it.
-- The shared tail (validate, link the roster, insert driver_profiles, flip
-- role, audit) is create_driver_record() (20260825120700) -- also reused
-- unchanged. Nothing here duplicates it.

-- ---------------------------------------------------------------------------
-- 1. driver_invites
-- ---------------------------------------------------------------------------
-- A separate table from admin_invites (Spec 19), not a shared one with a
-- discriminator column: toda_zone_id is always required here, never
-- optional, and there is no "scope" concept for a driver invite at all --
-- the fields do not overlap cleanly enough to be worth conflating.
create table public.driver_invites (
  id                uuid primary key default gen_random_uuid(),
  email             text not null,
  toda_zone_id      uuid not null references public.toda_zones (id),
  -- Advisory roster match, same as create_driver_record's own p_body_number --
  -- a legitimate new member may not be on the roster copy this project holds.
  body_number       text,
  invited_by        uuid not null references public.profiles (id),
  -- sha256(token)::hex, never the raw token -- same reasoning admin_invites
  -- (Spec 19) documents: this token creates a real account.
  token_hash        text not null unique,
  status            text not null default 'pending'
                       check (status in ('pending', 'accepted', 'revoked')),
  created_at        timestamptz not null default now(),
  expires_at        timestamptz not null default (now() + interval '7 days'),
  accepted_at       timestamptz,
  accepted_user_id  uuid references public.profiles (id),
  constraint driver_invites_token_hash_length check (char_length(token_hash) = 64)
);

create index driver_invites_email_idx on public.driver_invites (email);

comment on table public.driver_invites is
  'One-time-use LGU-issued driver enrollment invites. The raw token is '
  'returned once by admin_create_driver_invite() and never stored -- only '
  'its sha256 hash is kept. See .pipeline/specs.md Spec 20.';

alter table public.driver_invites enable row level security;

create policy driver_invites_select_lgu
  on public.driver_invites for select
  using (public.is_admin(auth.uid()));

-- No insert/update/delete policy for anyone -- every write goes through the
-- RPCs below, matching admin_invites' own established shape.

-- ---------------------------------------------------------------------------
-- 2. Creating an invite (LGU only)
-- ---------------------------------------------------------------------------
create or replace function public.admin_create_driver_invite(
  p_email        text,
  p_toda_zone_id uuid,
  p_body_number  text default null
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
  -- LGU-only, matching admin_promote_commuter_to_driver's own existing
  -- restriction exactly -- not widened to TODA-scoped admins this pass, so
  -- both the invite and promote paths behave identically for the same admin.
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can invite a driver'
      using errcode = '42501';
  end if;

  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'a valid email address is required'
      using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.toda_zones where id = p_toda_zone_id and is_active
  ) then
    raise exception 'unknown or inactive TODA zone'
      using errcode = '23503';
  end if;

  -- Defence in depth: apps/admin_web already checks
  -- admin_preview_driver_candidate() before ever offering this path, but
  -- this function does not trust that client-side branching alone.
  if exists (select 1 from public.profiles where email = v_email) then
    raise exception 'this email already belongs to an account -- use the promote flow instead'
      using errcode = '23505';
  end if;

  -- A resend supersedes rather than piling up dead rows.
  update public.driver_invites
     set status = 'revoked'
   where email = v_email and status = 'pending';

  -- 64 hex characters from two gen_random_uuid() calls, same construction
  -- ride_share_links.token / admin_invites.token_hash both use.
  v_token := replace(gen_random_uuid()::text, '-', '')
          || replace(gen_random_uuid()::text, '-', '');

  insert into public.driver_invites
    (email, toda_zone_id, body_number, invited_by, token_hash)
  values
    (v_email, p_toda_zone_id, nullif(trim(p_body_number), ''), auth.uid(),
     encode(sha256(v_token::bytea), 'hex'))
  returning id into v_invite_id;

  insert into public.admin_audit_logs (actor_id, action, metadata)
  values (
    auth.uid(),
    'driver_invite.created',
    jsonb_build_object('invite_id', v_invite_id, 'toda_zone_id', p_toda_zone_id)
  );

  return v_token;
end;
$$;

comment on function public.admin_create_driver_invite(text, uuid, text) is
  'LGU-only. Mints a one-time driver enrollment invite token (returned '
  'once, never stored) for an email with no existing account.';

revoke execute on function public.admin_create_driver_invite(text, uuid, text) from public, anon;
grant execute on function public.admin_create_driver_invite(text, uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Revoking a pending invite (LGU only)
-- ---------------------------------------------------------------------------
create or replace function public.admin_revoke_driver_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can revoke a driver invite'
      using errcode = '42501';
  end if;

  update public.driver_invites
     set status = 'revoked'
   where id = p_invite_id and status = 'pending';

  if found then
    insert into public.admin_audit_logs (actor_id, action, metadata)
    values (auth.uid(), 'driver_invite.revoked', jsonb_build_object('invite_id', p_invite_id));
  end if;
end;
$$;

comment on function public.admin_revoke_driver_invite(uuid) is
  'LGU-only. Cancels a still-pending driver invite, e.g. a typo''d email.';

revoke execute on function public.admin_revoke_driver_invite(uuid) from public, anon;
grant execute on function public.admin_revoke_driver_invite(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Looking up an invite by token (public -- the driver has no session)
-- ---------------------------------------------------------------------------
-- Same shape as ride_share_view() / admin_invite_lookup(): a hand-picked
-- column list, zero rows for anything wrong without saying why. The zone
-- name is included so the accept page can say which TODA the driver is
-- joining -- a small trust signal before handing over a password.
create or replace function public.driver_invite_lookup(p_token text)
returns table (email text, toda_zone_name text)
language sql
stable
security definer
set search_path = ''
as $$
  select i.email, z.name
    from public.driver_invites i
    join public.toda_zones z on z.id = i.toda_zone_id
   where i.token_hash = encode(sha256(p_token::bytea), 'hex')
     and i.status = 'pending'
     and i.expires_at > now();
$$;

comment on function public.driver_invite_lookup(text) is
  'Anon-reachable. Resolves a pending, unexpired driver invite token to '
  'its locked email and TODA zone name. Zero rows for any invalid token.';

revoke execute on function public.driver_invite_lookup(text) from public;
grant execute on function public.driver_invite_lookup(text) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Finalizing an accepted invite (service_role only)
-- ---------------------------------------------------------------------------
-- Called by the accept-driver-invite Edge Function immediately after it
-- creates the auth user via the Auth Admin API. Deliberately thin: the
-- driver-record work is entirely create_driver_record() (20260825120700),
-- already granted to service_role, reused exactly as the existing
-- admin_activate_new_driver() path uses it -- same p_action tag
-- ('driver.activate'), so the audit trail reads identically regardless of
-- which of the two paths created the driver.
create or replace function public.driver_finalize_invited_account(
  p_invite_token text,
  p_user_id      uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.driver_invites%rowtype;
begin
  -- current_setting('role'), not current_user -- see admin_activate_new_driver
  -- (20260825120700) for why current_user is wrong inside a definer function.
  -- The GRANT below is the primary control; this is defence in depth.
  if coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'driver_finalize_invited_account: callable only by a trusted server process'
      using errcode = '42501';
  end if;

  select * into v_invite
    from public.driver_invites
   where token_hash = encode(sha256(p_invite_token::bytea), 'hex')
     and status = 'pending'
     and expires_at > now()
   for update;

  if not found then
    raise exception 'driver_finalize_invited_account: invite is no longer valid'
      using errcode = '42501';
  end if;

  perform public.create_driver_record(
    p_user_id, v_invite.invited_by, v_invite.toda_zone_id, v_invite.body_number,
    'Invited via email', 'driver.activate'
  );

  update public.driver_invites
     set status           = 'accepted',
         accepted_at      = now(),
         accepted_user_id = p_user_id
   where id = v_invite.id;
end;
$$;

comment on function public.driver_finalize_invited_account(text, uuid) is
  'service_role only. Promotes a freshly created auth user to driver via '
  'create_driver_record() once the Edge Function has created the account '
  'via the Auth Admin API, and marks the invite accepted.';

revoke execute on function public.driver_finalize_invited_account(text, uuid)
  from anon, authenticated;
grant execute on function public.driver_finalize_invited_account(text, uuid)
  to service_role;
