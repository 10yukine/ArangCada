-- Let an in-scope administrator correct a driver's operational record.
-- Phone stays on the authenticated phone-change OTP flow; this RPC must not
-- bypass proof of control over the new number.

create or replace function public.admin_update_driver_record(
  p_driver_id uuid,
  p_first_name text,
  p_last_name text,
  p_plate_number text,
  p_body_number text,
  p_toda_zone_id uuid,
  p_license_expires_on date
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_driver public.driver_profiles%rowtype;
  v_first_name text := nullif(btrim(p_first_name), '');
  v_last_name text := nullif(btrim(p_last_name), '');
  v_body_number text := nullif(btrim(p_body_number), '');
  v_plate_number text := nullif(upper(btrim(p_plate_number)), '');
begin
  if not exists (
    select 1 from public.profiles p
     where p.id = v_actor and p.role = 'admin' and p.status = 'active'
  ) then
    raise exception 'admin_update_driver_record: active administrator account is required'
      using errcode = '42501';
  end if;

  select * into v_driver
    from public.driver_profiles
   where id = p_driver_id
     for update;
  if not found then
    raise exception 'admin_update_driver_record: no such driver'
      using errcode = 'P0002';
  end if;
  if not public.has_admin_scope(v_actor, v_driver.toda_zone_id) then
    raise exception 'admin_update_driver_record: driver is outside the assigned TODA scope'
      using errcode = '42501';
  end if;
  if v_first_name is null or v_last_name is null then
    raise exception 'admin_update_driver_record: first and last names are required'
      using errcode = '22023';
  end if;
  if p_toda_zone_id is null or not exists (
    select 1 from public.toda_zones z where z.id = p_toda_zone_id and z.is_active
  ) then
    raise exception 'admin_update_driver_record: an active TODA is required'
      using errcode = '22023';
  end if;
  if not public.is_admin(v_actor) and p_toda_zone_id <> v_driver.toda_zone_id then
    raise exception 'admin_update_driver_record: only an LGU administrator can reassign a TODA'
      using errcode = '42501';
  end if;

  update public.profiles
     set first_name = v_first_name,
         last_name = v_last_name,
         display_name = v_first_name || ' ' || v_last_name,
         updated_at = now()
   where id = p_driver_id;

  update public.driver_profiles
     set plate_number = v_plate_number,
         body_number = v_body_number,
         toda_zone_id = p_toda_zone_id,
         license_expires_on = p_license_expires_on,
         updated_at = now()
   where id = p_driver_id;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)
  values (
    v_actor,
    'driver.update_record',
    p_driver_id,
    'Driver record updated by administrator'
  );
end;
$$;

revoke execute on function public.admin_update_driver_record(uuid, text, text, text, text, uuid, date) from anon;
grant execute on function public.admin_update_driver_record(uuid, text, text, text, text, uuid, date) to authenticated;

drop function public.admin_list_drivers();
create function public.admin_list_drivers()
returns table (
  driver_id uuid,
  display_name text,
  first_name text,
  last_name text,
  phone text,
  toda_zone_id uuid,
  toda_name text,
  body_number text,
  plate_number text,
  license_expires_on date,
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
    select d.id, p.display_name, p.first_name, p.last_name, p.phone,
      d.toda_zone_id, z.name, d.body_number, d.plate_number,
      d.license_expires_on, d.verification_status::text, p.status::text,
      coalesce(a.is_online, false), a.latitude, a.longitude,
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
