-- Trip places are kept for 30 days after a trip ends.
--
-- Pickup and destination names and coordinates can come from Google Places,
-- whose terms allow keeping a coordinate for at most 30 days and other place
-- content not at all beyond that. Trips do not record where a place came
-- from, so every finished trip older than 30 days loses its place details.
-- The fare, timestamps, zone, people and status stay; the labels become the
-- generic words the apps already fall back to.

create or replace function public.purge_trip_places(
  p_age interval default interval '30 days'
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
     where status in (
             'completed',
             'cancelled_by_rider',
             'cancelled_by_driver',
             'no_driver_available'
           )
       and coalesce(completed_at, updated_at) < now() - p_age
       and (not public.st_isempty(pickup)
            or not public.st_isempty(dropoff)
            or pickup_label <> 'Pickup'
            or destination_label <> 'Destination')
    returning 1
  )
  select count(*)::integer from purged;
$$;

comment on function public.purge_trip_places(interval) is
  'Clears pickup/destination names and coordinates from trips that ended '
  'longer ago than p_age (30 days by default), for Google Places terms. '
  'Returns the number of trips changed. Status is untouched, so no push '
  'notification fires.';

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
      '41 3 * * *',
      $cron$select public.purge_trip_places()$cron$
    );
  else
    raise notice 'pg_cron unavailable; purge_trip_places() must be scheduled manually';
  end if;
end
$$;
