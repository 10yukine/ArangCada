begin;
-- Defaults OFF. Enable only after written approval, fee collection readiness,
-- and a minimum mobile build that discloses the full policy. No historical
-- fares are recalculated. Fare fields are snapshots, not remittance receipts.
alter table public.mobile_settings
  add column app_fare_enabled boolean not null default false;
alter table public.trips
  add column app_fare_version text,
  add column fare_class_at_booking public.passenger_fare_class,
  add column base_trip_fare numeric(8,2),
  add column service_supplement numeric(8,2) not null default 0 check (service_supplement >= 0),
  add column system_fee numeric(8,2) not null default 0 check (system_fee >= 0);

create function public.trips_snapshot_app_fare()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_enabled boolean;
begin
  select fare_class into new.fare_class_at_booking from public.profiles where id = new.rider_id;
  new.app_fare_version := null;
  new.service_supplement := 0;
  new.system_fee := 0;
  new.base_trip_fare := new.fare_estimate;
  select app_fare_enabled into v_enabled from public.mobile_settings where id;
  if v_enabled and new.ride_type = 'special' then
    new.base_trip_fare := public.compute_fare(new.distance_m, new.ride_type, new.fare_class_at_booking, new.passenger_count);
    new.app_fare_version := 'app-fare-v1';
    new.service_supplement := case when new.passenger_count <= 2 then 10 when new.passenger_count = 3 then 15 else 20 end;
    new.system_fee := 5;
    -- Provisional discount policy: confirm the scope before enabling.
    if new.fare_class_at_booking = 'discounted' then
      new.service_supplement := new.service_supplement * 0.8;
      new.system_fee := 4;
    end if;
    new.fare_estimate := new.base_trip_fare + new.service_supplement + new.system_fee;
  end if;
  return new;
end;
$$;
revoke all on function public.trips_snapshot_app_fare() from public, anon, authenticated;
-- PostgreSQL orders same-kind triggers alphabetically: snapshot before pickup.
create trigger trips_00_snapshot_app_fare before insert on public.trips
for each row execute function public.trips_snapshot_app_fare();

-- Standalone pickup compatibility; app-fare-v1 uses max(premium, allowance).
alter table public.mobile_settings
  add column charge_pickup_leg boolean not null default false,
  add column pickup_free_m integer not null default 500
    check (pickup_free_m >= 0);

alter table public.trips
  add column pickup_distance_m integer check (pickup_distance_m >= 0),
  add column pickup_fare numeric check (pickup_fare >= 0);

comment on column public.trips.pickup_distance_m is
  'Straight-line metres from the assigned driver to the pickup when the booking was given to them. Recorded whether or not the pickup charge is on.';
comment on column public.trips.pickup_fare is
  'Calculated pickup allowance; app-fare-v1 includes it through max(service premium, pickup allowance), never as an additional stacked charge. Null for an unpriced pickup.';

create or replace function public.trips_add_pickup_leg()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver   public.driver_availability%rowtype;
  v_settings public.mobile_settings%rowtype;
  v_bracket  public.fare_matrix%rowtype;
  v_billed   integer;
  v_rate     integer;
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
  -- A trip with no fare has nothing to add to.
  if (not v_settings.charge_pickup_leg and new.app_fare_version is null) or new.fare_estimate is null then
    return new;
  end if;

  -- The same bracket compute_fare reads for this ride type.
  select * into v_bracket
    from public.fare_matrix
   where ride_type = new.ride_type
     and is_active
   limit 1;

  if not found then
    return new;
  end if;

  -- Only the metres beyond the free distance are charged, and never more than
  -- the search can reach.
  v_billed := greatest(
    least(new.pickup_distance_m,
          case when new.app_fare_version is not null then 3000 else (select s.widened_radius_m from public.dispatch_settings s where s.id) end)
      - case when new.app_fare_version is not null then 500 else v_settings.pickup_free_m end,
    0);

  v_rate := case
    when new.app_fare_version = 'app-fare-v1' then
      case when new.fare_class_at_booking = 'discounted' then 640 else 800 end
    when new.fare_class_at_booking = 'discounted' then v_bracket.discount_per_km_centavos
    else v_bracket.per_km_centavos
  end;

  -- Metres x centavos per kilometre, to whole pesos.
  new.pickup_fare := round(v_billed::numeric * v_rate / 100000);
  if new.app_fare_version is not null then
    new.service_supplement := greatest(new.service_supplement, new.pickup_fare);
    new.fare_estimate := new.base_trip_fare + new.service_supplement + new.system_fee;
  else
    new.fare_estimate := new.fare_estimate + new.pickup_fare;
  end if;
  return new;
end;
$$;

revoke all on function public.trips_add_pickup_leg() from public, anon, authenticated;

create trigger trips_add_pickup_leg
  before insert or update of driver_id on public.trips
  for each row execute function public.trips_add_pickup_leg();

create or replace function public.get_mobile_settings()
returns jsonb language sql stable security definer set search_path = '' as $$
select jsonb_build_object(
  'min_mobile_build', s.min_mobile_build, 'routing', s.routing, 'search', s.search,
  'app_fare_enabled', s.app_fare_enabled,
  'pickup_free_m', case when s.app_fare_enabled then 500 when s.charge_pickup_leg then s.pickup_free_m else 0 end,
  'pickup_charge_max_m', case when s.app_fare_enabled then 2500 when s.charge_pickup_leg then greatest((select widened_radius_m from public.dispatch_settings where id) - s.pickup_free_m, 0) else 0 end
) from public.mobile_settings s where s.id;
$$;

-- Patch the fully migrated definition, preserving admin booking, fresh-driver
-- dispatch and all later guards rather than copying an older function body.
do $patch$
declare
  definition text := pg_get_functiondef('public.request_ride(double precision,double precision,double precision,double precision,text,text,text)'::regprocedure);
  item record;
begin
  for item in select * from (values
    ('p_idempotency_key text)', 'p_idempotency_key text, p_passenger_count integer DEFAULT NULL)'),
    ('  if nullif(trim(coalesce(p_idempotency_key, '''')), '''') is null',
     '  if p_passenger_count is null and (select app_fare_enabled from public.mobile_settings where id) then
    raise exception ''Fares changed. Reopen the app and review your fare before booking.'' using errcode = ''22023'';
  end if;
  p_passenger_count := coalesce(p_passenger_count, 1);
  if p_passenger_count not between 1 and 4 then
    raise exception ''passenger count must be between 1 and 4'' using errcode = ''22023'';
  end if;
  if nullif(trim(coalesce(p_idempotency_key, '''')), '''') is null'),
    ('    distance_m, fare_estimate, idempotency_key, pickup_label,',
     '    passenger_count, distance_m, fare_estimate, idempotency_key, pickup_label,'),
    ('    v_distance,', '    p_passenger_count, v_distance,'),
    ('v_rider.fare_class, 1)', 'v_rider.fare_class, p_passenger_count)')
  ) as p(anchor,replacement) loop
    if (length(definition)-length(replace(definition,item.anchor,''))) <> length(item.anchor) then
      raise exception 'request_ride changed; review staged fare migration (anchor: %)', item.anchor;
    end if;
    definition := replace(definition,item.anchor,item.replacement);
  end loop;
  drop function public.request_ride(double precision,double precision,double precision,double precision,text,text,text);
  execute definition;
end;
$patch$;
revoke execute on function public.request_ride(double precision,double precision,double precision,double precision,text,text,text,integer) from public,anon;
grant execute on function public.request_ride(double precision,double precision,double precision,double precision,text,text,text,integer) to authenticated,service_role;

-- Preserve the fare-bearing count after the quote is issued.
create or replace function public.set_trip_passenger_count(
  p_trip_id uuid,
  p_passenger_count integer
)
returns public.trips
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_trip public.trips%rowtype;
  v_cap  integer;
begin
  select * into v_trip
    from public.trips
   where id = p_trip_id
   for update;

  if auth.uid() is null or not found or v_trip.rider_id is distinct from auth.uid() then
    raise exception 'that trip does not belong to you'
      using errcode = '42501';
  end if;

  if v_trip.status not in ('requested', 'searching_driver', 'driver_assigned', 'accepted') then
    raise exception 'passenger count can no longer be changed on this trip'
      using errcode = '22023';
  end if;

  if v_trip.app_fare_version is not null and p_passenger_count is distinct from v_trip.passenger_count then
    raise exception 'cancel and book again to change the quoted passenger count' using errcode = '22023';
  end if;

  select coalesce(operating_max_passengers, max_passengers) into v_cap
    from public.fare_matrix
   where ride_type = v_trip.ride_type and is_active;

  if p_passenger_count is null or p_passenger_count < 1 or p_passenger_count > v_cap then
    raise exception '% passengers is outside the permitted range of 1-%',
      p_passenger_count, v_cap
      using errcode = '22023';
  end if;

  update public.trips
     set passenger_count = p_passenger_count, updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  return v_trip;
end;
$$;


commit;
