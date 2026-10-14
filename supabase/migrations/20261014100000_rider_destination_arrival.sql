-- A commuter may report destination arrival only while the driver's GPS is
-- stale. Keep only the distance and source in the audit log, never their GPS.
create function public.rider_reached_destination(
  p_trip_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_meters double precision
)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_updated_at timestamptz;
  v_distance double precision;
begin
  -- Trip first, then availability: the same order as driver GPS/completion.
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.rider_id is distinct from auth.uid() then
    raise exception 'only the trip commuter can report destination arrival'
      using errcode = '42501';
  end if;
  if v_trip.status <> 'in_progress' then
    raise exception 'destination arrival requires an in-progress trip'
      using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null or p_accuracy_meters is null
     or p_lat not between -90 and 90 or p_lng not between -180 and 180
     or p_accuracy_meters not between 0 and 50 then
    raise exception 'a precise current commuter GPS fix is required'
      using errcode = '22023';
  end if;

  v_distance := public.st_distancesphere(
    public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326), v_trip.dropoff
  );
  if v_distance is null or v_distance > 100 then
    raise exception 'commuter destination arrival requires proximity'
      using errcode = '22023';
  end if;

  select updated_at into v_updated_at from public.driver_availability
   where driver_id = v_trip.driver_id for share;
  if v_updated_at is null
     or v_updated_at >= clock_timestamp() - interval '30 seconds' then
    raise exception 'commuter destination arrival requires stale driver GPS'
      using errcode = '22023';
  end if;

  if v_trip.completion_available_at is null then
    update public.trips
       set completion_available_at = now() + interval '60 seconds',
           updated_at = now()
     where id = p_trip_id
     returning * into v_trip;
    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    values (p_trip_id, auth.uid(), 'ride.destination_radius_entered',
            jsonb_build_object('source', 'rider', 'distance_m', v_distance));
  end if;
  return v_trip;
end;
$$;

revoke all on function public.rider_reached_destination(uuid, double precision, double precision, double precision)
  from public, anon;
grant execute on function public.rider_reached_destination(uuid, double precision, double precision, double precision)
  to authenticated;

-- Preserve complete_trip's existing driver path and all subsequent fare,
-- feedback and audit behavior; replace only the commuter proximity guard.
do $$
declare
  v_definition text;
  v_anchor text := $anchor$       or v_location.latitude is null
       or public.st_distancesphere(
            public.st_setsrid(
              public.st_makepoint(v_location.longitude, v_location.latitude), 4326
            ),
            v_trip.dropoff
          ) > 100$anchor$;
  v_replacement text := $replacement$       or not (
         coalesce(public.st_distancesphere(
           public.st_setsrid(
             public.st_makepoint(v_location.longitude, v_location.latitude), 4326
           ), v_trip.dropoff
         ) <= 100, false)
         or (
           coalesce(v_location.updated_at < clock_timestamp() - interval '30 seconds', false)
           and exists (
             select 1 from public.trip_events e
              where e.trip_id = v_trip.id
                and e.actor_id = v_trip.rider_id
                and e.event_type = 'ride.destination_radius_entered'
                and e.metadata ->> 'source' = 'rider'
           )
         )
       )$replacement$;
begin
  v_definition := pg_get_functiondef('public.complete_trip(uuid)'::regprocedure);
  if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
     <> length(v_anchor) then
    raise exception 'complete_trip changed; review the commuter arrival guard';
  end if;
  v_definition := replace(v_definition, v_anchor, v_replacement);
  -- Hold the availability row so a fresh, distant fix cannot race completion.
  v_anchor := 'select * into v_location from public.driver_availability
     where driver_id = v_trip.driver_id;';
  if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
     <> length(v_anchor) then
    raise exception 'complete_trip changed; review the availability lock';
  end if;
  v_definition := replace(v_definition, v_anchor,
    'select * into v_location from public.driver_availability
     where driver_id = v_trip.driver_id for update;');
  execute v_definition;
end;
$$;
