-- The driver marks arrival at the pickup point, or completes a trip, only
-- within 100 m of that point by their own GPS from the last 30 seconds, or
-- after the commuter agrees in the app: "My driver is here" covers a meeting
-- point away from the pin, "Stop here" a stop before the drop-off point. The
-- fare stays the quoted fare either way (complete_trip keeps fare_estimate).

alter table public.trips
  add column rider_confirmed_pickup_at timestamptz,
  add column rider_requested_stop_at timestamptz;

comment on column public.trips.rider_confirmed_pickup_at is
  'Set by rider_confirm_pickup: the commuter says the driver is with them, so the driver may mark arrival away from the pickup point.';
comment on column public.trips.rider_requested_stop_at is
  'Set by rider_request_stop: the commuter asks to stop early, so the driver may complete the trip away from the drop-off point.';

create function public.rider_confirm_pickup(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.rider_id is distinct from auth.uid() then
    raise exception 'only the trip commuter can confirm the driver is here'
      using errcode = '42501';
  end if;
  if v_trip.status = 'arrived' or v_trip.rider_confirmed_pickup_at is not null then
    return v_trip;
  end if;
  if v_trip.status not in ('accepted', 'driver_en_route') then
    raise exception 'the driver can be confirmed only while they are on the way'
      using errcode = '22023';
  end if;
  update public.trips
     set rider_confirmed_pickup_at = now(), updated_at = now()
   where id = p_trip_id
   returning * into v_trip;
  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.rider_confirmed_pickup');
  return v_trip;
end;
$$;

create function public.rider_request_stop(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.rider_id is distinct from auth.uid() then
    raise exception 'only the trip commuter can ask to stop here'
      using errcode = '42501';
  end if;
  if v_trip.rider_requested_stop_at is not null then
    return v_trip;
  end if;
  if v_trip.status <> 'in_progress' then
    raise exception 'a stop can be requested only during the trip'
      using errcode = '22023';
  end if;
  update public.trips
     set rider_requested_stop_at = now(), updated_at = now()
   where id = p_trip_id
   returning * into v_trip;
  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.rider_requested_stop');
  return v_trip;
end;
$$;

revoke all on function public.rider_confirm_pickup(uuid) from public, anon;
revoke all on function public.rider_request_stop(uuid) from public, anon;
grant execute on function public.rider_confirm_pickup(uuid) to authenticated;
grant execute on function public.rider_request_stop(uuid) to authenticated;

-- Patched in place, as 20261014100000 does. Each anchor must occur exactly
-- once or the migration stops before changing anything.
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.mark_arrived(uuid)'::regprocedure,
       $anchor$  if v_trip.status not in ('accepted', 'driver_en_route') then
    raise exception 'arrival requires an accepted ride'
      using errcode = '22023';
  end if;
$anchor$,
       $replacement$  if v_trip.status not in ('accepted', 'driver_en_route') then
    raise exception 'arrival requires an accepted ride'
      using errcode = '22023';
  end if;
  if v_trip.rider_confirmed_pickup_at is null and not exists (
    select 1 from public.driver_availability a
     where a.driver_id = v_trip.driver_id
       and a.updated_at >= clock_timestamp() - interval '30 seconds'
       and public.st_distancesphere(
             public.st_setsrid(public.st_makepoint(a.longitude, a.latitude), 4326),
             v_trip.pickup
           ) <= 100
  ) then
    raise exception 'arrival requires current driver GPS within 100 m of the pickup point, or the commuter''s confirmation'
      using errcode = '22023';
  end if;
$replacement$),
      ('public.complete_trip(uuid)'::regprocedure,
       $anchor$  update public.trips
     set status = 'completed',$anchor$,
       $replacement$  if auth.uid() = v_trip.driver_id
     and v_trip.rider_requested_stop_at is null
     and not exists (
       select 1 from public.driver_availability a
        where a.driver_id = v_trip.driver_id
          and a.updated_at >= clock_timestamp() - interval '30 seconds'
          and public.st_distancesphere(
                public.st_setsrid(public.st_makepoint(a.longitude, a.latitude), 4326),
                v_trip.dropoff
              ) <= 100
     ) then
    raise exception 'driver completion requires current GPS within 100 m of the drop-off point, or the commuter''s request to stop'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'completed',$replacement$)
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the trip step proximity migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;
