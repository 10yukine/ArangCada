-- Migration: admin_update_driver_name
-- Allows LGU and TODA administrators to edit a driver's first and last name.
-- Updates public.profiles (first_name, last_name, display_name) and driver_profiles (updated_at).
-- Logs action to public.admin_audit_logs.
-- Also widens admin_list_drivers() to return first_name, last_name, and phone.

-- 1. admin_update_driver_name RPC
create or replace function public.admin_update_driver_name(
  p_driver_id  uuid,
  p_first_name text,
  p_last_name  text,
  p_reason     text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid := auth.uid();
  v_driver     public.driver_profiles%rowtype;
  v_first_name text;
  v_last_name  text;
  v_full_name  text;
begin
  if not exists (
    select 1 from public.profiles p
     where p.id = v_actor and p.role = 'admin' and p.status = 'active'
  ) then
    raise exception 'admin_update_driver_name: active administrator account is required'
      using errcode = '42501';
  end if;

  select * into v_driver
    from public.driver_profiles
   where id = p_driver_id
     for update;

  if not found then
    raise exception 'admin_update_driver_name: no such driver'
      using errcode = 'P0002';
  end if;

  if not public.has_admin_scope(v_actor, v_driver.toda_zone_id) then
    raise exception 'admin_update_driver_name: driver name update is restricted to the assigned TODA or LGU'
      using errcode = '42501';
  end if;

  v_first_name := trim(coalesce(p_first_name, ''));
  v_last_name := trim(coalesce(p_last_name, ''));

  if v_first_name = '' or v_last_name = '' then
    raise exception 'admin_update_driver_name: both first name and last name are required'
      using errcode = '22023';
  end if;

  v_full_name := v_first_name || ' ' || v_last_name;

  update public.profiles
     set first_name = v_first_name,
         last_name = v_last_name,
         display_name = v_full_name,
         updated_at = now()
   where id = p_driver_id;

  update public.driver_profiles
     set updated_at = now()
   where id = p_driver_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (
    v_actor,
    'driver.update_name',
    p_driver_id,
    coalesce(p_reason, 'Driver name updated by administrator')
  );
end;
$$;

comment on function public.admin_update_driver_name(uuid, text, text, text) is
  'Allows an in-scope administrator (LGU or matching TODA) to update a driver''s name. '
  'Updates profiles and writes an audit log entry.';

revoke execute on function public.admin_update_driver_name(uuid, text, text, text) from anon;
grant execute on function public.admin_update_driver_name(uuid, text, text, text) to authenticated;

-- 2. Widen admin_list_drivers to include first_name, last_name, phone
drop function if exists public.admin_list_drivers();

create or replace function public.admin_list_drivers()
returns table (
  driver_id uuid,
  display_name text,
  first_name text,
  last_name text,
  phone text,
  toda_zone_id uuid,
  toda_name text,
  body_number text,
  verification_status text,
  account_status text,
  is_online boolean,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles p
     where p.id = auth.uid() and p.role = 'admin' and p.status = 'active'
  ) then
    raise exception 'an active administrator account is required'
      using errcode = '42501';
  end if;

  return query
    select
      d.id,
      p.display_name,
      p.first_name,
      p.last_name,
      p.phone,
      d.toda_zone_id,
      z.name,
      d.body_number,
      d.verification_status::text,
      p.status::text,
      coalesce(a.is_online, false),
      a.latitude,
      a.longitude,
      coalesce(a.updated_at, d.updated_at)
      from public.driver_profiles d
      join public.profiles p on p.id = d.id
      join public.toda_zones z on z.id = d.toda_zone_id
      left join public.driver_availability a on a.driver_id = d.id
     where public.has_admin_scope(auth.uid(), d.toda_zone_id)
     order by p.display_name;
end;
$$;

revoke execute on function public.admin_list_drivers() from anon;
grant execute on function public.admin_list_drivers() to authenticated;
