-- Driver onboarding: the admin-facing RPCs.
--
-- THE MODEL
--
-- A driver coordinates with an administrator face-to-face and hands over their
-- documents, email, and mobile number together. The administrator then either
-- promotes an account the person already has, or creates one for them. Nothing
-- in the commuter app offers to become a driver.
--
-- ArangCada never issues credentials even though the admin creates the
-- account: the Edge Function generates a one-time invite link and the driver
-- sets their own password. The admin originates the identity; only the driver
-- ever knows the secret.
--
-- WHY EVERY MUTATION LIVES HERE INSTEAD OF IN AN RLS WRITE POLICY
--
-- driver_profiles and profiles both refuse direct writes from an authenticated
-- session. If an administrator could PATCH verification_status through
-- PostgREST, an approval would leave no admin_audit_logs row, and "every
-- promote, demote, approve, reject, suspend, and unsuspend writes exactly one
-- audit row" would be aspirational rather than true. These functions are
-- security definer, so they execute as the function owner and need no write
-- policy at all -- which is exactly why none exists.

-- ---------------------------------------------------------------------------
-- Name masking
-- ---------------------------------------------------------------------------
-- An administrator resolving a person by mobile number should see enough to
-- confirm they have the right account and no more. 'Juan Dela Cruz' becomes
-- 'J*** D*** C***': recognisable to someone standing in front of the person,
-- useless as a directory dump.
create or replace function public.mask_name(p_name text)
returns text
language sql
immutable
as $$
  select nullif(
    (
      select string_agg(
               left(w, 1) || repeat('*', greatest(char_length(w) - 1, 0)),
               ' ' order by ord
             )
        from unnest(
               string_to_array(
                 regexp_replace(coalesce(trim(p_name), ''), '\s+', ' ', 'g'),
                 ' '
               )
             ) with ordinality as t(w, ord)
       where w <> ''
    ),
    ''
  );
$$;

comment on function public.mask_name(text) is
  'Keeps the first letter of each word, masks the rest. Used so an admin '
  'lookup confirms identity without returning a readable name.';

revoke execute on function public.mask_name(text) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Candidate lookup
-- ---------------------------------------------------------------------------
-- Returns up to two INDEPENDENT rows, one per identifier that matched. They
-- are deliberately not collapsed: if the email belongs to one account and the
-- mobile number to a different one, that is a discrepancy a human must resolve
-- -- a typo, two accounts for one person, or the wrong person entirely. A
-- function that silently picked one would make exactly the mistake the
-- confirm step exists to prevent.
--
-- Returns NO uuid. The administrator learns nothing they did not already hold;
-- the promotion below re-derives the account server-side from the identifier
-- rather than trusting a client-supplied id.
create or replace function public.admin_preview_driver_candidate(
  p_email text default null,
  p_phone text default null
)
returns table (
  match_key      text,
  masked_name    text,
  joined_on      date,
  account_role   public.user_role,
  account_status public.profile_status,
  trip_count     integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_phone text := public.normalize_ph_mobile(p_phone);
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'admin_preview_driver_candidate: admin privileges required'
      using errcode = '42501';
  end if;

  return query
    select m.key,
           public.mask_name(p.display_name),
           p.created_at::date,
           p.role,
           p.status,
           (select count(*)::integer from public.trips t where t.rider_id = p.id)
      from (values ('email', v_email), ('phone', v_phone)) as m(key, val)
      join public.profiles p
        on (m.key = 'email' and p.email = m.val)
        or (m.key = 'phone' and p.phone = m.val)
     where m.val is not null;
end;
$$;

comment on function public.admin_preview_driver_candidate(text, text) is
  'Up to two independent matches, one per identifier, deliberately not merged. '
  'Returns a masked name and no uuid.';

revoke execute on function public.admin_preview_driver_candidate(text, text) from anon;

-- ---------------------------------------------------------------------------
-- Shared driver-record creation
-- ---------------------------------------------------------------------------
-- The promotion and activation paths differ only in how the target account is
-- found. Everything after that -- validate the zone, link the roster, insert
-- the driver record, flip the role, write the audit row -- is identical, so it
-- lives here once. Internal: not granted to any client role.
create or replace function public.create_driver_record(
  p_target_id    uuid,
  p_actor_id     uuid,
  p_toda_zone_id uuid,
  p_body_number  text,
  p_reason       text,
  p_action       text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member_id uuid;
  v_role      public.user_role;
  v_status    public.profile_status;
begin
  select role, status into v_role, v_status
    from public.profiles where id = p_target_id;

  if not found then
    raise exception 'create_driver_record: no such profile' using errcode = 'P0002';
  end if;

  if v_role <> 'commuter' then
    raise exception 'create_driver_record: account is already a %, not a commuter', v_role
      using errcode = '22023';
  end if;

  if v_status <> 'active' then
    raise exception 'create_driver_record: account is suspended and cannot be promoted'
      using errcode = '22023';
  end if;

  if not exists (select 1 from public.toda_zones z
                  where z.id = p_toda_zone_id and z.is_active) then
    raise exception 'create_driver_record: unknown or inactive TODA zone'
      using errcode = '23503';
  end if;

  -- Roster match is advisory: recorded when found, never required. A stale or
  -- incomplete roster must not make a legitimate new member unonboardable.
  if p_body_number is not null then
    select id into v_member_id
      from public.toda_members
     where toda_zone_id = p_toda_zone_id
       and body_number  = p_body_number
       and is_active
     limit 1;
  end if;

  insert into public.driver_profiles
    (id, toda_zone_id, toda_member_id, body_number, promoted_by)
  values
    (p_target_id, p_toda_zone_id, v_member_id, p_body_number, p_actor_id);

  update public.profiles
     set role = 'driver', updated_at = now()
   where id = p_target_id;

  -- metadata carries uuids and flags only; admin_audit_logs' check constraint
  -- rejects identity-bearing keys outright.
  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason, metadata)
  values (
    p_actor_id, p_action, p_target_id, p_reason,
    jsonb_build_object(
      'toda_zone_id',      p_toda_zone_id,
      'body_number_given', (p_body_number is not null),
      'roster_matched',    (v_member_id is not null)
    )
  );

  return p_target_id;
end;
$$;

comment on function public.create_driver_record(uuid, uuid, uuid, text, text, text) is
  'Internal. Shared tail of the promote and activate paths: validate, link the '
  'roster advisorily, insert the driver record, flip the role, audit.';

revoke execute on function public.create_driver_record(uuid, uuid, uuid, text, text, text)
  from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Promote an account the person already has
-- ---------------------------------------------------------------------------
-- p_match_by names which identifier the admin is acting on, resolving the
-- two-different-matches case the preview deliberately leaves open.
--
-- p_confirm_value must be re-entered by hand: the full email, or the last four
-- digits of the mobile number. It is the safeguard against a mistyped
-- identifier silently promoting an uninvolved commuter -- a real risk, because
-- role is one-way for everyone except an administrator acting before
-- verification.
create or replace function public.admin_promote_commuter_to_driver(
  p_match_by      text,
  p_email         text default null,
  p_phone         text default null,
  p_confirm_value text default null,
  p_toda_zone_id  uuid default null,
  p_body_number   text default null,
  p_reason        text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor  uuid := auth.uid();
  v_email  text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_phone  text := public.normalize_ph_mobile(p_phone);
  v_target uuid;
begin
  if not public.is_admin(v_actor) then
    raise exception 'admin_promote_commuter_to_driver: admin privileges required'
      using errcode = '42501';
  end if;

  if p_match_by not in ('email', 'phone') then
    raise exception 'admin_promote_commuter_to_driver: match_by must be email or phone'
      using errcode = '22023';
  end if;

  if p_match_by = 'email' then
    if v_email is null then
      raise exception 'admin_promote_commuter_to_driver: email required when matching by email'
        using errcode = '22023';
    end if;
    if lower(trim(coalesce(p_confirm_value, ''))) <> v_email then
      raise exception 'admin_promote_commuter_to_driver: confirmation does not match the email given'
        using errcode = '22023';
    end if;
    select id into v_target from public.profiles where email = v_email;
  else
    if v_phone is null then
      raise exception 'admin_promote_commuter_to_driver: a valid PH mobile number is required when matching by phone'
        using errcode = '22023';
    end if;
    if coalesce(p_confirm_value, '') <> right(v_phone, 4) then
      raise exception 'admin_promote_commuter_to_driver: confirmation does not match the last four digits'
        using errcode = '22023';
    end if;
    select id into v_target from public.profiles where phone = v_phone;
  end if;

  if v_target is null then
    raise exception 'admin_promote_commuter_to_driver: no account matches that identifier'
      using errcode = 'P0002';
  end if;

  return public.create_driver_record(
    v_target, v_actor, p_toda_zone_id, p_body_number, p_reason, 'driver.promote'
  );
end;
$$;

comment on function public.admin_promote_commuter_to_driver(text, text, text, text, uuid, text, text) is
  'Promotes an existing commuter account to driver. Re-derives the account '
  'server-side; never accepts a client-supplied profile id. Requires the '
  'identifier to be confirmed by hand.';

revoke execute on function public.admin_promote_commuter_to_driver(text, text, text, text, uuid, text, text)
  from anon;

-- ---------------------------------------------------------------------------
-- Activate an account the Edge Function just created
-- ---------------------------------------------------------------------------
-- DELIBERATELY NOT ADMIN-CALLABLE. Execute is granted to service_role only,
-- so no ordinary admin session can reach it -- the Edge Function calls it with
-- a service-role client immediately after auth.admin.generateLink() created
-- the user.
--
-- The reason for the asymmetry: this function takes a profile id directly
-- rather than re-deriving one from an identifier. That is safe only because
-- the caller just created that id and cannot be mistaken about it. Exposing
-- the same shape to an admin session would reintroduce the client-supplied-id
-- trust that admin_promote_commuter_to_driver exists to avoid.
--
-- p_actor_id is passed explicitly because a service_role connection has no
-- auth.uid(); the Edge Function supplies the admin it already authenticated.
create or replace function public.admin_activate_new_driver(
  p_new_profile_id uuid,
  p_actor_id       uuid,
  p_toda_zone_id   uuid,
  p_body_number    text default null,
  p_reason         text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  -- current_setting('role'), NOT current_user.
  --
  -- Inside a SECURITY DEFINER function current_user is the function OWNER, so
  -- `current_user <> 'service_role'` would raise for every caller including
  -- the legitimate one -- the first version of this guard did exactly that and
  -- was caught by probing rather than by assuming. The role GUC is what
  -- survives the definer switch and still reports the effective role.
  --
  -- Note the deliberate contrast with guard_profiles_privileged_columns()
  -- (20260825120100), which tests current_user precisely BECAUSE it changes
  -- inside a definer function: that is how the trigger lets these RPCs write
  -- role/status while still blocking a raw PATCH from the same admin session.
  -- Opposite mechanisms, opposite requirements, both correct.
  --
  -- The GRANT below is the primary control; this is defence in depth. A role
  -- cannot SET ROLE to something it is not a member of, so an authenticated
  -- session cannot spoof its way past this.
  if coalesce(current_setting('role', true), '') <> 'service_role' then
    raise exception 'admin_activate_new_driver: callable only by a trusted server process'
      using errcode = '42501';
  end if;

  -- Defence in depth: the Edge Function already verified its caller against a
  -- JWT-scoped client, but this function must not depend on that having
  -- happened correctly.
  if not public.is_admin(p_actor_id) then
    raise exception 'admin_activate_new_driver: actor is not an active admin'
      using errcode = '42501';
  end if;

  return public.create_driver_record(
    p_new_profile_id, p_actor_id, p_toda_zone_id, p_body_number, p_reason, 'driver.activate'
  );
end;
$$;

comment on function public.admin_activate_new_driver(uuid, uuid, uuid, text, text) is
  'Marks a freshly created account as a driver. service_role only -- the Edge '
  'Function calls it right after creating the auth user.';

revoke execute on function public.admin_activate_new_driver(uuid, uuid, uuid, text, text)
  from anon, authenticated;
grant execute on function public.admin_activate_new_driver(uuid, uuid, uuid, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Undo a mis-promotion
-- ---------------------------------------------------------------------------
-- Only while unverified. Once a driver is reviewed, demotion would sever the
-- link between a person and their dispatch record, so it stops being an
-- in-app action and becomes an out-of-band SQL correction. Suspension, not
-- demotion, is the answer to a driver who has done something wrong.
create or replace function public.admin_demote_driver(
  p_driver_id uuid,
  p_reason    text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor  uuid := auth.uid();
  v_status public.driver_verification_status;
begin
  if not public.is_admin(v_actor) then
    raise exception 'admin_demote_driver: admin privileges required'
      using errcode = '42501';
  end if;

  select verification_status into v_status
    from public.driver_profiles where id = p_driver_id;

  if not found then
    raise exception 'admin_demote_driver: no such driver' using errcode = 'P0002';
  end if;

  if v_status <> 'unverified' then
    raise exception 'admin_demote_driver: driver is already % -- suspend them instead, or ask a developer for an out-of-band correction', v_status
      using errcode = '22023';
  end if;

  -- The documents belong to someone who was never a driver. Leaving them would
  -- orphan verification metadata against a commuter. The matching Storage
  -- objects must be deleted alongside this.
  delete from public.driver_documents where driver_id = p_driver_id;
  delete from public.driver_profiles   where id = p_driver_id;

  update public.profiles
     set role = 'commuter', updated_at = now()
   where id = p_driver_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (v_actor, 'driver.demote', p_driver_id, p_reason);
end;
$$;

revoke execute on function public.admin_demote_driver(uuid, text) from anon;

-- ---------------------------------------------------------------------------
-- Suspend / reinstate
-- ---------------------------------------------------------------------------
-- The disciplinary tool, and the one that works at any stage. Reversible, and
-- it preserves the driver's history rather than unpicking it.
create or replace function public.admin_set_profile_status(
  p_profile_id uuid,
  p_status     public.profile_status,
  p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
begin
  if not public.is_admin(v_actor) then
    raise exception 'admin_set_profile_status: admin privileges required'
      using errcode = '42501';
  end if;

  if p_profile_id = v_actor then
    raise exception 'admin_set_profile_status: an admin cannot change their own status'
      using errcode = '22023';
  end if;

  if p_status = 'suspended'
     and nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'admin_set_profile_status: a reason is required to suspend an account'
      using errcode = '22023';
  end if;

  update public.profiles
     set status = p_status, updated_at = now()
   where id = p_profile_id;

  if not found then
    raise exception 'admin_set_profile_status: no such profile' using errcode = 'P0002';
  end if;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (
    v_actor,
    case when p_status = 'suspended' then 'profile.suspend' else 'profile.unsuspend' end,
    p_profile_id,
    p_reason
  );
end;
$$;

revoke execute on function public.admin_set_profile_status(uuid, public.profile_status, text) from anon;

-- ---------------------------------------------------------------------------
-- Review a driver
-- ---------------------------------------------------------------------------
-- Approval is the moment a person becomes dispatchable, so it checks the
-- documents itself rather than trusting the reviewing administrator to have
-- looked. Every required document must exist AND have been individually
-- approved.
create or replace function public.admin_review_driver(
  p_driver_id uuid,
  p_decision  text,
  p_reason    text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor      uuid := auth.uid();
  v_status     public.driver_verification_status;
  v_unapproved integer;
begin
  if not public.is_admin(v_actor) then
    raise exception 'admin_review_driver: admin privileges required'
      using errcode = '42501';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'admin_review_driver: decision must be approve or reject'
      using errcode = '22023';
  end if;

  select verification_status into v_status
    from public.driver_profiles where id = p_driver_id;

  if not found then
    raise exception 'admin_review_driver: no such driver' using errcode = 'P0002';
  end if;

  if p_decision = 'reject' then
    if nullif(trim(coalesce(p_reason, '')), '') is null then
      raise exception 'admin_review_driver: a reason is required to reject a driver'
        using errcode = '22023';
    end if;

    update public.driver_profiles
       set verification_status = 'rejected',
           rejection_reason    = p_reason,
           reviewed_by         = v_actor,
           reviewed_at         = now(),
           updated_at          = now()
     where id = p_driver_id;

    insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
    values (v_actor, 'driver.reject', p_driver_id, p_reason);
    return;
  end if;

  select count(*)
    into v_unapproved
    from unnest(public.driver_required_document_types()) as t(dt)
   where not exists (
           select 1
             from public.driver_documents d
            where d.driver_id     = p_driver_id
              and d.document_type = t.dt
              and d.status        = 'approved'
         );

  if v_unapproved > 0 then
    raise exception 'admin_review_driver: % required document(s) are missing or not yet approved', v_unapproved
      using errcode = '22023';
  end if;

  update public.driver_profiles
     set verification_status = 'approved',
         rejection_reason    = null,
         reviewed_by         = v_actor,
         reviewed_at         = now(),
         updated_at          = now()
   where id = p_driver_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (v_actor, 'driver.approve', p_driver_id, p_reason);
end;
$$;

comment on function public.admin_review_driver(uuid, text, text) is
  'Approve or reject a driver. Approval re-checks that every required document '
  'exists and is itself approved, rather than trusting the reviewer.';

revoke execute on function public.admin_review_driver(uuid, text, text) from anon;
