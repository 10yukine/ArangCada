-- Dispatch: staged search radius (1 km, widening to 3 km).
--
-- Calamba City Hall, 31 August 2026. Having removed the TODA-jurisdiction
-- filter (see 20260831090000_nearest_driver_dispatch.sql), candidate selection
-- became unbounded: the previous migration orders every online driver in the
-- city by distance and takes the first. That will happily assign a driver
-- 12 km away, which is worse for everyone -- the commuter waits, the driver
-- burns fuel on an unpaid approach, and the trip looks absurd on the admin
-- monitor.
--
-- City Hall asked for a small radius first so a genuinely nearby driver gets
-- the ride, widening only if nobody close responds.
--
-- WHY THE VALUES ARE CONFIGURABLE RATHER THAN HARDCODED
--
-- The project owner's meeting notes read "5 mins zoning after open for
-- booking"; their verbal account of the same meeting said 3 minutes. Rather
-- than silently pick one and present it as the client's decision, the interval
-- is an LGU-editable setting -- the same treatment app_evaluation_settings
-- already gives the Objective 4 feedback interval -- defaulted to the shorter,
-- more commuter-favourable 180 s. The open question is recorded in
-- .pipeline/spec-city-hall-dispatch-revisions.md section 11 for the next
-- consultation.
--
-- WHAT THIS DOES NOT CHANGE
--
-- No fare change: Ordinance 743 is distance-based and the radius affects who
-- is assigned, not what anyone pays. No trip_status change: a search that
-- finds nobody uses the existing 'searching_driver' and 'no_driver_available'
-- values. No new client authority: the radius is applied inside the
-- SECURITY DEFINER function, so a modified app cannot widen its own search.

create table if not exists public.dispatch_settings (
  id                  boolean primary key default true check (id),
  initial_radius_m    integer not null default 1000
    check (initial_radius_m between 100 and 50000),
  widened_radius_m    integer not null default 3000
    check (widened_radius_m between 100 and 50000),
  widen_after_seconds integer not null default 180
    check (widen_after_seconds between 15 and 3600),
  updated_by          uuid references public.profiles (id),
  updated_at          timestamptz not null default now(),
  constraint dispatch_settings_radius_order
    check (widened_radius_m >= initial_radius_m)
);

comment on table public.dispatch_settings is
  'Single-row LGU-configurable dispatch tuning. Calamba City Hall, 31 Aug 2026: '
  'driver search starts at initial_radius_m and widens to widened_radius_m '
  'after widen_after_seconds. Read by request_ride; never trusted from a client.';
comment on column public.dispatch_settings.widen_after_seconds is
  'Seconds a trip may sit in searching_driver before the widened radius applies. '
  'Default 180. Meeting notes said 5 min, the verbal account said 3 min; '
  'unresolved, hence configurable. See spec-city-hall-dispatch-revisions.md.';

insert into public.dispatch_settings (id) values (true)
  on conflict (id) do nothing;

alter table public.dispatch_settings enable row level security;

-- Read: any signed-in user. The commuter app shows the search radius on the
-- "searching for driver" map, so it needs to know what it is. These are
-- operational tuning numbers, not personal data.
create policy dispatch_settings_select_authenticated
  on public.dispatch_settings for select
  to authenticated
  using (true);

-- Write: LGU admin only. No insert policy and no delete policy -- the single
-- row is created by this migration and must stay exactly one row.
create policy dispatch_settings_update_admin
  on public.dispatch_settings for update
  to authenticated
  using (public.is_admin((select auth.uid())))
  with check (public.is_admin((select auth.uid())));

-- Index supporting the distance-bounded candidate scan.
create index if not exists driver_availability_online_position_idx
  on public.driver_availability (is_online)
  where is_online;

-- Helper: the effective radius for a trip that has been searching since
-- p_since. Kept as a function so request_ride and any retry path cannot drift
-- apart on the rule.
create or replace function public.dispatch_radius_m(p_since timestamptz)
returns integer
language sql
stable
security definer
set search_path to ''
as $$
  select case
           when p_since is null then s.initial_radius_m
           when now() - p_since >= make_interval(secs => s.widen_after_seconds)
             then s.widened_radius_m
           else s.initial_radius_m
         end
    from public.dispatch_settings s
   where s.id;
$$;

comment on function public.dispatch_radius_m(timestamptz) is
  'Effective driver-search radius in metres for a trip searching since p_since. '
  'Null p_since means a first-pass search. Single source of the widening rule.';

revoke execute on function public.dispatch_radius_m(timestamptz)
  from public, anon;
grant execute on function public.dispatch_radius_m(timestamptz)
  to authenticated, service_role;

-- request_ride: bound the candidate scan by the first-pass radius.
--
-- Only the candidate query changes. Everything else -- the commuter check, the
-- idempotency replay, the coordinate validation, both service-area checks, the
-- internal-tester isolation, the fare call, the trip insert, the trip event --
-- is carried over verbatim from 20260831090000_nearest_driver_dispatch.sql.
create or replace function public.request_ride(p_pickup_lat double precision, p_pickup_lng double precision, p_destination_lat double precision, p_destination_lng double precision, p_pickup_label text, p_destination_label text, p_idempotency_key text)
 returns public.trips
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_rider public.profiles%rowtype;
  v_zone public.toda_zones%rowtype;
  v_destination_zone public.toda_zones%rowtype;
  v_trip public.trips%rowtype;
  v_driver_id uuid;
  v_driver_name text;
  v_pickup public.geometry;
  v_dropoff public.geometry;
  v_distance integer;
  v_radius_m integer;
begin
  select * into v_rider
    from public.profiles
   where id = auth.uid()
   for update;

  if not found or v_rider.role <> 'commuter' or v_rider.status <> 'active' then
    raise exception 'an active commuter account is required to request a ride'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'a booking idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_trip
    from public.trips
   where idempotency_key = p_idempotency_key;

  if found then
    if v_trip.rider_id <> v_rider.id then
      raise exception 'that booking key belongs to another commuter'
        using errcode = '42501';
    end if;
    return v_trip;
  end if;

  if p_pickup_lat is null or p_pickup_lng is null
     or p_destination_lat is null or p_destination_lng is null
     or p_pickup_lat not between -90 and 90
     or p_destination_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180
     or p_destination_lng not between -180 and 180 then
    raise exception 'valid pickup and destination coordinates are required'
      using errcode = '22023';
  end if;

  -- Service-area check, endpoint 1. Not a jurisdiction check: the covering
  -- TODA is recorded for oversight, it no longer restricts matching.
  select z.* into v_zone
    from public.toda_zone_covering(p_pickup_lng, p_pickup_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found then
    raise exception 'pickup is outside the Calamba service area'
      using errcode = '22023';
  end if;

  if v_zone.is_internal_test and not v_rider.is_internal_tester then
    raise exception 'the Cabuyao exception is restricted to developer-test identities'
      using errcode = '42501';
  end if;

  -- Service-area check, endpoint 2.
  select z.* into v_destination_zone
    from public.toda_zone_covering(p_destination_lng, p_destination_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found or (v_destination_zone.is_internal_test and not v_rider.is_internal_tester) then
    raise exception 'destination is outside the Calamba/internal-test service area'
      using errcode = '22023';
  end if;

  v_pickup := public.st_setsrid(public.st_makepoint(p_pickup_lng, p_pickup_lat), 4326);
  v_dropoff := public.st_setsrid(public.st_makepoint(p_destination_lng, p_destination_lat), 4326);
  v_distance := round(public.st_distancesphere(v_pickup, v_dropoff))::integer;

  -- First-pass search: the initial (narrow) radius.
  v_radius_m := public.dispatch_radius_m(null);

  select availability.driver_id, driver_profile.display_name
    into v_driver_id, v_driver_name
    from public.driver_availability availability
    join public.driver_profiles driver on driver.id = availability.driver_id
    join public.profiles driver_profile on driver_profile.id = driver.id
   where availability.is_online
     and public.can_driver_go_online(driver.id)
     and driver_profile.is_internal_tester = v_zone.is_internal_test
     and availability.latitude is not null
     and availability.longitude is not null
     and public.st_distancesphere(
           v_pickup,
           public.st_setsrid(
             public.st_makepoint(availability.longitude, availability.latitude), 4326)
         ) <= v_radius_m
     and not exists (
       select 1 from public.driver_feedback_obligations pending
        where pending.driver_id = driver.id and pending.submitted_at is null
     )
   order by
     public.st_distancesphere(
       v_pickup,
       public.st_setsrid(
         public.st_makepoint(availability.longitude, availability.latitude), 4326)
     ),
     availability.updated_at desc
   for update of availability skip locked
   limit 1;

  -- Note on the change of behaviour for drivers with no GPS fix: the previous
  -- migration sorted them last but still allowed them to be matched. A radius
  -- cannot be evaluated for a driver whose position is unknown, and assuming
  -- such a driver is "near" would defeat the rule City Hall asked for. They are
  -- therefore excluded while a radius applies. A driver who is genuinely online
  -- will have a fix; one who does not is not demonstrably nearby.

  if v_driver_id is not null then
    update public.driver_availability
       set is_online = false, updated_at = now()
     where driver_id = v_driver_id;
  end if;

  insert into public.trips (
    rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
    distance_m, fare_estimate, idempotency_key, pickup_label,
    destination_label, rider_display_name, driver_display_name, toda_name,
    payment_method, accept_by
  )
  values (
    v_rider.id,
    v_driver_id,
    v_zone.id,
    'special',
    case when v_driver_id is null
         then 'searching_driver'::public.trip_status
         else 'driver_assigned'::public.trip_status end,
    v_pickup,
    v_dropoff,
    v_distance,
    public.compute_fare(v_distance, 'special', 'standard', 1),
    p_idempotency_key,
    coalesce(trim(p_pickup_label), ''),
    coalesce(trim(p_destination_label), ''),
    v_rider.display_name,
    v_driver_name,
    v_zone.name,
    'cash',
    case when v_driver_id is not null then now() + interval '30 seconds' end
  )
  returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (
    v_trip.id,
    v_rider.id,
    'ride.requested',
    jsonb_build_object('assigned', v_driver_id is not null, 'radius_m', v_radius_m)
  );

  return v_trip;
end;
$function$;

-- retry_dispatch: the widening pass.
--
-- Called by the commuter's client while it sits on the "searching for driver"
-- screen, and safe to call repeatedly. The radius it uses is derived from how
-- long the trip has actually been searching, read from the row itself -- so a
-- client that calls this immediately does NOT get the widened radius. The
-- widening is time-based on the server, not request-based from the app.
create or replace function public.retry_dispatch(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_trip public.trips%rowtype;
  v_driver_id uuid;
  v_driver_name text;
  v_radius_m integer;
  v_widened_m integer;
begin
  select * into v_trip
    from public.trips
   where id = p_trip_id
   for update;

  if not found or v_trip.rider_id <> auth.uid() then
    raise exception 'that trip does not belong to you'
      using errcode = '42501';
  end if;

  if v_trip.status <> 'searching_driver' then
    return v_trip;
  end if;

  v_radius_m := public.dispatch_radius_m(v_trip.requested_at);
  select s.widened_radius_m into v_widened_m from public.dispatch_settings s where s.id;

  select availability.driver_id, driver_profile.display_name
    into v_driver_id, v_driver_name
    from public.driver_availability availability
    join public.driver_profiles driver on driver.id = availability.driver_id
    join public.profiles driver_profile on driver_profile.id = driver.id
    join public.toda_zones z on z.id = v_trip.toda_zone_id
   where availability.is_online
     and public.can_driver_go_online(driver.id)
     and driver_profile.is_internal_tester = z.is_internal_test
     and availability.latitude is not null
     and availability.longitude is not null
     and public.st_distancesphere(
           v_trip.pickup,
           public.st_setsrid(
             public.st_makepoint(availability.longitude, availability.latitude), 4326)
         ) <= v_radius_m
     and not exists (
       select 1 from public.driver_feedback_obligations pending
        where pending.driver_id = driver.id and pending.submitted_at is null
     )
   order by
     public.st_distancesphere(
       v_trip.pickup,
       public.st_setsrid(
         public.st_makepoint(availability.longitude, availability.latitude), 4326)
     ),
     availability.updated_at desc
   for update of availability skip locked
   limit 1;

  if v_driver_id is not null then
    update public.driver_availability
       set is_online = false, updated_at = now()
     where driver_id = v_driver_id;

    update public.trips
       set driver_id = v_driver_id,
           driver_display_name = v_driver_name,
           status = 'driver_assigned',
           accept_by = now() + interval '30 seconds',
           updated_at = now()
     where id = v_trip.id
     returning * into v_trip;

    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    values (v_trip.id, v_trip.rider_id, 'ride.assigned_on_retry',
            jsonb_build_object('radius_m', v_radius_m));

  elsif v_radius_m >= v_widened_m then
    -- The widened radius has already been tried and still found nobody. Tell
    -- the commuter honestly rather than leaving them on a spinner forever.
    update public.trips
       set status = 'no_driver_available', updated_at = now()
     where id = v_trip.id
     returning * into v_trip;

    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    values (v_trip.id, v_trip.rider_id, 'ride.no_driver_available',
            jsonb_build_object('radius_m', v_radius_m));
  end if;

  return v_trip;
end;
$function$;

comment on function public.retry_dispatch(uuid) is
  'Re-runs driver matching for the caller''s own searching trip at the radius '
  'earned by elapsed time. Idempotent and safe to poll. Gives up with '
  'no_driver_available once the widened radius has been tried.';

revoke execute on function public.retry_dispatch(uuid) from public, anon;
grant execute on function public.retry_dispatch(uuid) to authenticated, service_role;

revoke execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  from public, anon;
grant execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  to authenticated, service_role;
