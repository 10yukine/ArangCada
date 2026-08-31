-- Dispatch: nearest available driver, city-wide.
--
-- Calamba City Hall reviewed the TODA-jurisdiction dispatch model and asked for
-- nearest-driver matching instead, the way commuters already expect from Grab.
-- This implements that decision.
--
-- WHAT CHANGED (three lines inside request_ride)
--
-- 1. Candidate drivers are no longer filtered to the pickup's TODA. Previously
--    `availability.toda_zone_id = v_zone.id` meant a commuter standing beside an
--    idle driver from a neighbouring TODA could not be matched to them.
--
-- 2. Candidates are ordered by actual distance from the pickup, not by
--    `updated_at desc`. Worth stating plainly: the old rule was not "nearest"
--    at all -- it picked whichever driver had most recently sent a heartbeat,
--    which is arbitrary with respect to where anyone actually is.
--    driver_availability already carries latitude/longitude, so no new data is
--    needed. Drivers with no fix sort last rather than being excluded, so a
--    stale-GPS driver is still reachable when nobody else is.
--
-- 3. `(not v_zone.is_internal_test or driver_profile.is_internal_tester)`
--    becomes `driver_profile.is_internal_tester = v_zone.is_internal_test`.
--    This one is not cosmetic. The TODA filter was implicitly keeping
--    developer-test drivers inside the Cabuyao test zone; removing it would
--    have let a test driver be dispatched to a real commuter's ride. The
--    equality restores that isolation explicitly, in both directions.
--
-- WHAT DID NOT CHANGE
--
-- Pickup and destination must still fall inside some TODA polygon. That check
-- is the service-area boundary, not jurisdiction: CLAUDE.md scope rule 1 is
-- "Calamba City only", and the union of TODA polygons is the only city-shaped
-- boundary in the schema. Dropping it would accept a booking from anywhere on
-- earth. If City Hall wants the service area widened too, that needs its own
-- decision and a Calamba boundary polygon to check against.
--
-- trips.toda_zone_id still records the pickup's TODA, so governance, admin
-- scoping and per-TODA reporting are unaffected. Objective 1's oversight story
-- survives; only the matching rule changed.
--
-- KNOWN CONSEQUENCE, needs a governance decision
--
-- A driver from TODA A can now serve a pickup inside TODA B. trips_select_scoped_admin
-- filters on trips.toda_zone_id, so B's admin sees that trip and A's admin --
-- the driver's own TODA -- does not. Under jurisdiction dispatch those were
-- always the same TODA, so the question never arose. Left unchanged here
-- because widening admin visibility is an authorization change, not a dispatch
-- one, and it should be decided deliberately rather than smuggled in.
--
-- Ride type stays hardcoded 'special' (Espesyal). City Hall confirmed Espesyal-
-- only operation; that was already this function's behaviour, so no fare change
-- is involved and Ordinance 743 remains transcribed exactly as posted.

CREATE OR REPLACE FUNCTION public.request_ride(p_pickup_lat double precision, p_pickup_lng double precision, p_destination_lat double precision, p_destination_lng double precision, p_pickup_label text, p_destination_label text, p_idempotency_key text)
 RETURNS trips
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_rider public.profiles%rowtype;
  v_zone public.toda_zones%rowtype;
  v_destination_zone public.toda_zones%rowtype;
  v_trip public.trips%rowtype;
  v_driver_id uuid;
  v_driver_name text;
  v_pickup public.geometry;
  v_dropoff public.geometry;
  v_distance integer;
begin
  select * into v_rider
    from public.profiles
   where id = auth.uid()
   for update;

  if not found or v_rider.role <> 'commuter' or v_rider.status <> 'active' then
    raise exception 'an active commuter account is required to request a ride'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'a booking idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_trip
    from public.trips
   where idempotency_key = p_idempotency_key;

  if found then
    if v_trip.rider_id <> v_rider.id then
      raise exception 'that booking key belongs to another commuter'
        using errcode = '42501';
    end if;
    return v_trip;
  end if;

  if p_pickup_lat is null or p_pickup_lng is null
     or p_destination_lat is null or p_destination_lng is null
     or p_pickup_lat not between -90 and 90
     or p_destination_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180
     or p_destination_lng not between -180 and 180 then
    raise exception 'valid pickup and destination coordinates are required'
      using errcode = '22023';
  end if;

  select z.* into v_zone
    from public.toda_zone_covering(p_pickup_lng, p_pickup_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found then
    raise exception 'pickup is outside all approved or developer-test TODA jurisdictions'
      using errcode = '22023';
  end if;

  if v_zone.is_internal_test and not v_rider.is_internal_tester then
    raise exception 'the Cabuyao exception is restricted to developer-test identities'
      using errcode = '42501';
  end if;

  select z.* into v_destination_zone
    from public.toda_zone_covering(p_destination_lng, p_destination_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found or (v_destination_zone.is_internal_test and not v_rider.is_internal_tester) then
    raise exception 'destination is outside the Calamba/internal-test service area'
      using errcode = '22023';
  end if;

  v_pickup := public.st_setsrid(public.st_makepoint(p_pickup_lng, p_pickup_lat), 4326);
  v_dropoff := public.st_setsrid(public.st_makepoint(p_destination_lng, p_destination_lat), 4326);
  v_distance := round(public.st_distancesphere(v_pickup, v_dropoff))::integer;

  select availability.driver_id, driver_profile.display_name
    into v_driver_id, v_driver_name
    from public.driver_availability availability
    join public.driver_profiles driver on driver.id = availability.driver_id
    join public.profiles driver_profile on driver_profile.id = driver.id
   where availability.is_online
     and public.can_driver_go_online(driver.id)
     and driver_profile.is_internal_tester = v_zone.is_internal_test
     and not exists (
       select 1 from public.driver_feedback_obligations pending
        where pending.driver_id = driver.id and pending.submitted_at is null
     )
   order by
     case when availability.latitude is null or availability.longitude is null
          then 1 else 0 end,
     public.st_distancesphere(
       v_pickup,
       public.st_setsrid(
         public.st_makepoint(availability.longitude, availability.latitude), 4326)
     ),
     availability.updated_at desc
   for update of availability skip locked
   limit 1;

  if v_driver_id is not null then
    update public.driver_availability
       set is_online = false, updated_at = now()
     where driver_id = v_driver_id;
  end if;

  insert into public.trips (
    rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
    distance_m, fare_estimate, idempotency_key, pickup_label,
    destination_label, rider_display_name, driver_display_name, toda_name,
    payment_method, accept_by
  )
  values (
    v_rider.id,
    v_driver_id,
    v_zone.id,
    'special',
    case when v_driver_id is null
         then 'searching_driver'::public.trip_status
         else 'driver_assigned'::public.trip_status end,
    v_pickup,
    v_dropoff,
    v_distance,
    public.compute_fare(v_distance, 'special', 'standard', 1),
    p_idempotency_key,
    coalesce(trim(p_pickup_label), ''),
    coalesce(trim(p_destination_label), ''),
    v_rider.display_name,
    v_driver_name,
    v_zone.name,
    'cash',
    case when v_driver_id is not null then now() + interval '30 seconds' end
  )
  returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (
    v_trip.id,
    v_rider.id,
    'ride.requested',
    jsonb_build_object('assigned', v_driver_id is not null)
  );

  return v_trip;
end;
$function$;
