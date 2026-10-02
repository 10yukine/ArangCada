-- Replace the completion-based retention clock. Preserve fares, status and participants.
create or replace function public.purge_trip_places(
  p_age interval default interval '29 days'
)
returns integer
language sql
security definer
set search_path = ''
as $$
  with purged as (
    update public.trips
       set pickup_label = 'Pickup',
           destination_label = 'Destination',
           -- The lat/lng columns are generated from these; an empty point
           -- keeps the NOT NULL columns valid and turns those into null.
           pickup = public.st_geomfromtext('POINT EMPTY', 4326),
           dropoff = public.st_geomfromtext('POINT EMPTY', 4326)
     where requested_at < now() - least(p_age, interval '29 days')
       and (not public.st_isempty(pickup)
            or not public.st_isempty(dropoff)
            or pickup_label <> 'Pickup'
            or destination_label <> 'Destination')
    returning 1
  )
  select count(*)::integer from purged;
$$;

comment on function public.purge_trip_places(interval) is
  'Clears trip place content by request age, capped at 29 days, regardless of status. '
  'New clients reject Google coordinates older than one hour before booking. '
  'An hourly sweep leaves margin below the 30-day coordinate limit.';

revoke execute on function public.purge_trip_places(interval)
  from public, anon, authenticated;
grant execute on function public.purge_trip_places(interval) to service_role;

-- Same guard as sweep_abandoned_registrations: schedule only where pg_cron
-- exists, so local stacks without it still migrate.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    perform cron.unschedule('purge-trip-places')
      where exists (select 1 from cron.job where jobname = 'purge-trip-places');

    perform cron.schedule(
      'purge-trip-places',
      '41 * * * *',
      $cron$select public.purge_trip_places()$cron$
    );
  else
    raise notice 'pg_cron unavailable; purge_trip_places() must be scheduled manually';
  end if;
end
$$;
