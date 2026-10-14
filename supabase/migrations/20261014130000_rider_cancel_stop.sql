-- The commuter can take back "Get off early" (rider_request_stop) while the
-- trip is still running, so the driver's 100 m completion rule applies again.
create function public.rider_cancel_stop(p_trip_id uuid)
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
    raise exception 'only the trip commuter can take back a request to get off early'
      using errcode = '42501';
  end if;
  if v_trip.rider_requested_stop_at is null then
    return v_trip;
  end if;
  if v_trip.status <> 'in_progress' then
    raise exception 'a request to get off early can be taken back only during the trip'
      using errcode = '22023';
  end if;
  update public.trips
     set rider_requested_stop_at = null, updated_at = now()
   where id = p_trip_id
   returning * into v_trip;
  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.rider_cancelled_stop');
  return v_trip;
end;
$$;

revoke all on function public.rider_cancel_stop(uuid) from public, anon;
grant execute on function public.rider_cancel_stop(uuid) to authenticated;
