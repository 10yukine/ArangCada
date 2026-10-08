-- The fare covers the driver's way to the pickup, beyond a free distance.
--
-- Owner, 8 Oct 2026, approved by the group's capstone adviser. This is not an
-- LGU approval: Ordinance 743 prices the trip, and nothing here records the
-- LGU agreeing to a charge for the way to the pickup.
--
-- A driver within mobile_settings.pickup_free_m of the pickup (600 m) costs
-- nothing extra. For a driver farther away, the metres beyond that are added
-- to the trip's metres and the total is read from the same ordinance table in
-- one lookup: a 2.6 km trip with the driver 1.8 km away is billed as
-- 2.6 + 1.2 km.
--
-- The free distance is its own number, not a search range. Dispatch already
-- gives a booking to the nearest driver, so searching a smaller range first
-- would only make a commuter wait for the driver they get anyway.
--
-- Both distances are straight lines, as the trip's has always been
-- (request_ride). The driver's is the one dispatch already measures to choose
-- the nearest driver, at the moment it assigns them. What is billed never
-- exceeds widened_radius_m - pickup_free_m, which is the largest amount the
-- app quotes before booking ("pickup charge up to ...").
--
-- A trip is given a driver in two places, request_ride and retry_dispatch,
-- and at most once: a declined or expired offer ends the trip. A trigger on
-- that one moment covers both without patching either.
--
--   trips.pickup_distance_m   the driver's metres to the pickup at that
--                             moment. Recorded on every assignment, charged
--                             or not, so the free distance can be set from
--                             what the pilot shows.
--   trips.pickup_fare         what was added; fare_estimate is the total.
--                             Null while the charge is off.
--
-- OFF until the owner switches it on:
--   update public.mobile_settings set charge_pickup_leg = true;
-- and the free distance is changed the same way:
--   update public.mobile_settings set pickup_free_m = 1000;
-- Builds up to 4057 do not tell the commuter about the charge before booking,
-- so switch it on only once a build that does is the minimum
-- (min_mobile_build). Both live in mobile_settings because no account can
-- change that table through the API; the app reads them through
-- get_mobile_settings as pickup_free_m and pickup_charge_max_m (both 0 while
-- off).
--
-- Regression: supabase/tests/100_pickup_leg_fare_test.sql
alter table public.mobile_settings
  add column charge_pickup_leg boolean not null default false,
  add column pickup_free_m integer not null default 600
    check (pickup_free_m >= 0);

alter table public.trips
  add column pickup_distance_m integer check (pickup_distance_m >= 0),
  add column pickup_fare numeric check (pickup_fare >= 0);

comment on column public.trips.pickup_distance_m is
  'Straight-line metres from the assigned driver to the pickup when the booking was given to them. Recorded whether or not the pickup leg is charged.';
comment on column public.trips.pickup_fare is
  'The part of fare_estimate added for the driver''s metres beyond mobile_settings.pickup_free_m; 0 for a driver inside it. Null when the charge was switched off.';

create function public.trips_add_pickup_leg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver   public.driver_availability%rowtype;
  v_settings public.mobile_settings%rowtype;
  v_billed   integer;
  v_total    numeric;
begin
  if new.driver_id is null
     or new.status <> 'driver_assigned'
     or new.pickup_distance_m is not null
     or (tg_op = 'UPDATE' and old.driver_id is not null) then
    return new;
  end if;

  select * into v_driver
    from public.driver_availability
   where driver_id = new.driver_id;

  if v_driver.latitude is null or v_driver.longitude is null then
    return new;
  end if;

  new.pickup_distance_m := round(public.st_distancesphere(
    new.pickup,
    public.st_setsrid(
      public.st_makepoint(v_driver.longitude, v_driver.latitude), 4326)
  ))::integer;

  select * into v_settings from public.mobile_settings where id;
  if not v_settings.charge_pickup_leg then
    return new;
  end if;

  -- Only the metres beyond the free distance are billed, and never more than
  -- the search can reach.
  v_billed := greatest(
    least(new.pickup_distance_m,
          (select s.widened_radius_m from public.dispatch_settings s where s.id))
      - v_settings.pickup_free_m,
    0);

  v_total := public.compute_fare(
    new.distance_m + v_billed,
    new.ride_type,
    (select p.fare_class from public.profiles p where p.id = new.rider_id),
    new.passenger_count);

  -- No price for the whole way: leave the trip's own fare as it is.
  if v_total is null or v_total < new.fare_estimate then
    return new;
  end if;

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
             case when s.charge_pickup_leg then s.pickup_free_m else 0 end,
           'pickup_charge_max_m',
             case when s.charge_pickup_leg
                  then greatest(
                         (select d.widened_radius_m
                            from public.dispatch_settings d where d.id)
                           - s.pickup_free_m,
                         0)
                  else 0 end)
    from public.mobile_settings s
   where s.id;
$$;
