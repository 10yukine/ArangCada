-- Expose only the other participant's registered phone during an accepted ride.
-- Never grant broad profile access for the dialer.
create or replace function public.trip_counterpart_phone(p_trip_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.phone
    from public.trips t
    join public.profiles p on p.id = case
      when t.rider_id = auth.uid() then t.driver_id else t.rider_id end
   where t.id = p_trip_id
     and auth.uid() is not null
     and (t.rider_id = auth.uid() or t.driver_id = auth.uid())
     and t.status in ('accepted', 'driver_en_route', 'arrived',
                      'in_progress', 'emergency_reported')
     and p.phone ~ '^\+639[0-9]{9}$';
$$;
revoke all on function public.trip_counterpart_phone(uuid) from public, anon;
grant execute on function public.trip_counterpart_phone(uuid) to authenticated;
comment on function public.trip_counterpart_phone(uuid) is
  'Active trip participants only; returns NULL for missing, unauthorized, ended, or unavailable contacts.';
