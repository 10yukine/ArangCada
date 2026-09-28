-- Pending invites stop working once the inviting admin loses admin rights
-- (security audit, 28 Sep 2026). Invites last up to 7 days; before this, an
-- admin suspended or demoted in that window could still have new admin or
-- driver accounts created on their authority. Both functions are their latest
-- definitions verbatim plus one check. The lookups the accept-invite pages and
-- edge functions call first get the same condition, so such an invite reads as
-- invalid before an auth account is created (finalize failing afterwards would
-- leave an orphaned account). Regression: 85_audit_followups_test.sql.

-- admin_finalize_invited_account: from 20260908020000_lgu_toda_admin_invites.sql
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

  -- The inviter must still hold the authority the invite was created with
  -- (admin_create_invite / admin_create_driver_invite check is_admin).
  -- A suspended or demoted admin's pending invites stop working.
  if not public.is_admin(v_invite.invited_by) then
    raise exception 'admin_finalize_invited_account: the administrator who sent this invite no longer has that authority'
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

-- driver_finalize_invited_account: from 20260909010000_driver_invites.sql
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

  -- The inviter must still hold the authority the invite was created with
  -- (admin_create_invite / admin_create_driver_invite check is_admin).
  -- A suspended or demoted admin's pending invites stop working.
  if not public.is_admin(v_invite.invited_by) then
    raise exception 'driver_finalize_invited_account: the administrator who sent this invite no longer has that authority'
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
     and i.expires_at > now()
     and public.is_admin(i.invited_by);
$$;

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
     and i.expires_at > now()
     and public.is_admin(i.invited_by);
$$;
