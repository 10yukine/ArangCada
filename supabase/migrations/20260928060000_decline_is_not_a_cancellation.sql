-- Declining a ride offer is not a cancellation.
--
-- decline_ride used to call cancel_ride, so a declined offer closed the trip
-- as cancelled_by_driver: the rider was told their driver cancelled, and the
-- admin dashboard would count it against the driver. Since 20260928050000
-- cancel_ride refuses drivers outright, so decline_ride failed instead
-- (found in the live two-phone beta test, 28 Sep 2026).
--
-- The owner's rule is the other way round: a driver who does not want a ride
-- should decline it. So a decline now ends the offer exactly like an unanswered
-- offer that expires (expire_ride): the trip becomes no_driver_available, the
-- rider sees "No drivers available" and can book again, and the driver goes
-- back online. It is logged as ride.declined, never as a cancellation.

create or replace function public.decline_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the offered driver can decline this ride'
      using errcode = '42501';
  end if;
  if v_trip.status = 'no_driver_available' then
    return v_trip;
  end if;
  if v_trip.status <> 'driver_assigned' then
    raise exception 'only an unanswered ride offer can be declined'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'no_driver_available', updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  update public.driver_availability
     set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
   where driver_id = v_trip.driver_id;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.declined');

  return v_trip;
end;
$$;

revoke execute on function public.decline_ride(uuid) from public, anon;
grant execute on function public.decline_ride(uuid) to authenticated, service_role;
