-- The fare covers the driver's way to the pickup, beyond the first search range.
--
-- Owner, 8 Oct 2026, approved by the group's capstone adviser. This is not an
-- LGU approval: Ordinance 743 prices the trip, and nothing here records the
-- LGU agreeing to a charge for the way to the pickup.
--
-- Dispatch first looks for a driver within initial_radius_m (1 km) and only
-- later within widened_radius_m (3 km). A driver found in the first range
-- costs nothing extra, as before. For a driver farther than that, the metres
-- beyond the first range are added to the trip's metres and the total is read
-- from the same ordinance table in one lookup: a 2.6 km trip with the driver
-- 1.8 km away is billed as 2.6 + 0.8 km.
--
-- Both distances are straight lines, as the trip's has always been
-- (request_ride). The driver's is the one dispatch already measures to choose
-- the nearest driver, at the moment it assigns them. It never exceeds the
-- widened range, so the most that is ever added is the fare for
-- widened_radius_m - initial_radius_m, which is what the app quotes before
-- booking ("pickup charge up to ...").
--
-- A trip is given a driver in two places, request_ride and retry_dispatch,
-- and at most once: a declined or expired offer ends the trip. A trigger on
-- that one moment covers both without patching either.
--
--   trips.pickup_distance_m   the driver's metres to the pickup at that moment
--   trips.pickup_fare         what they added; fare_estimate is the total
--
-- OFF until the owner switches it on:
--   update public.mobile_settings set charge_pickup_leg = true;
-- Builds up to 4057 do not tell the commuter about the charge before booking,
-- so switch it on only once a build that does is the minimum
-- (min_mobile_build). The switch lives in mobile_settings because no account
-- can change that table through the API; the app reads it through
-- get_mobile_settings as pickup_free_m and pickup_charge_max_m (both 0 while
-- off).
--
-- Regression: supabase/tests/100_pickup_leg_fare_test.sql
alter table public.mobile_settings
  add column charge_pickup_leg boolean not null default false;

alter table public.trips
  add column pickup_distance_m integer check (pickup_distance_m >= 0),
  add column pickup_fare numeric check (pickup_fare >= 0);

comment on column public.trips.pickup_distance_m is
  'Straight-line metres from the assigned driver to the pickup when the booking was given to them, capped at the widened search radius. Null when the pickup leg was not considered (the charge was switched off).';
comment on column public.trips.pickup_fare is
  'The part of fare_estimate added for the driver''s metres beyond the first search range; 0 for a driver inside it. Null when the charge was switched off.';

create function public.trips_add_pickup_leg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.driver_availability%rowtype;
  v_ranges public.dispatch_settings%rowtype;
  v_leg    integer;
  v_total  numeric;
begin
  if new.driver_id is null
     or new.status <> 'driver_assigned'
     or new.pickup_distance_m is not null
     or (tg_op = 'UPDATE' and old.driver_id is not null)
     or not (select s.charge_pickup_leg from public.mobile_settings s where s.id) then
    return new;
  end if;

  select * into v_driver
    from public.driver_availability
   where driver_id = new.driver_id;

  if v_driver.latitude is null or v_driver.longitude is null then
    return new;
  end if;

  select * into v_ranges from public.dispatch_settings where id;

  v_leg := least(
    round(public.st_distancesphere(
      new.pickup,
      public.st_setsrid(
        public.st_makepoint(v_driver.longitude, v_driver.latitude), 4326)
    ))::integer,
    v_ranges.widened_radius_m);

  -- The first search range is free; only the metres beyond it are billed.
  v_total := public.compute_fare(
    new.distance_m + greatest(v_leg - v_ranges.initial_radius_m, 0),
    new.ride_type,
    (select p.fare_class from public.profiles p where p.id = new.rider_id),
    new.passenger_count);

  -- No price for the whole way: leave the trip's own fare as it is.
  if v_total is null or v_total < new.fare_estimate then
    return new;
  end if;

  new.pickup_distance_m := v_leg;
  new.pickup_fare := v_total - new.fare_estimate;
  new.fare_estimate := v_total;
  return new;
end;
$$;

revoke all on function public.trips_add_pickup_leg() from public, anon, authenticated;

create trigger trips_add_pickup_leg
  before insert or update of driver_id on public.trips
  for each row execute function public.trips_add_pickup_leg();

create or replace function public.get_mobile_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'min_mobile_build', s.min_mobile_build,
           'routing', s.routing,
           'search', s.search,
           'pickup_free_m',
             case when s.charge_pickup_leg
                  then (select d.initial_radius_m
                          from public.dispatch_settings d where d.id)
                  else 0 end,
           'pickup_charge_max_m',
             case when s.charge_pickup_leg
                  then (select d.widened_radius_m - d.initial_radius_m
                          from public.dispatch_settings d where d.id)
                  else 0 end)
    from public.mobile_settings s
   where s.id;
$$;
