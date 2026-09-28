-- Driver cancellations are a last resort, reported for TODA/LGU review.
--
-- Owner rule (28 Sep 2026): a driver who does not want a ride should not
-- accept it; cancelling after accepting alerts the administrators and may
-- lead to penalties. So:
--   * drivers can no longer use cancel_ride (which let them cancel at any
--     time, mid-trip included, with no reason);
--   * cancel_ride_as_driver allows it only before the trip starts
--     (accepted / en route / arrived), requires one of four reasons, stores
--     the reason on the trip and records it in trip_events for review.
-- Riders keep cancel_ride unchanged.

create or replace function public.cancel_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
    raise exception 'only a trip participant can cancel this ride'
      using errcode = '42501';
  end if;

  if auth.uid() = v_trip.driver_id then
    raise exception 'drivers cancel with cancel_ride_as_driver and a reason'
      using errcode = '42501';
  end if;

  if v_trip.status = 'cancelled_by_rider' then
    return v_trip;
  end if;

  if v_trip.status in ('completed', 'cancelled_by_rider', 'cancelled_by_driver', 'no_driver_available') then
    raise exception 'a closed trip cannot be cancelled again'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'cancelled_by_rider', cancellation_reason = 'cancelled_by_rider', updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  if v_trip.driver_id is not null then
    update public.driver_availability
       set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
     where driver_id = v_trip.driver_id;
  end if;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.cancelled_by_rider');

  return v_trip;
end;
$$;

create or replace function public.cancel_ride_as_driver(p_trip_id uuid, p_reason text)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  if p_reason is null or p_reason not in (
    'passenger_no_show', 'cannot_reach_pickup', 'vehicle_problem', 'safety_concern'
  ) then
    raise exception 'choose why you are cancelling this ride'
      using errcode = '22023';
  end if;

  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the assigned driver can cancel this ride'
      using errcode = '42501';
  end if;

  if v_trip.status = 'cancelled_by_driver' then
    return v_trip;
  end if;

  if v_trip.status not in ('accepted', 'driver_en_route', 'arrived') then
    raise exception 'a driver can only cancel before the trip starts'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'cancelled_by_driver', cancellation_reason = p_reason, updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  update public.driver_availability
     set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
   where driver_id = v_trip.driver_id;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (p_trip_id, auth.uid(), 'ride.cancelled_by_driver',
          jsonb_build_object('reason', p_reason));

  return v_trip;
end;
$$;

revoke execute on function public.cancel_ride_as_driver(uuid, text) from public, anon;
grant execute on function public.cancel_ride_as_driver(uuid, text) to authenticated, service_role;
