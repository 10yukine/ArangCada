-- Espesyal-only booking, operating cap of 4 passengers.
--
-- Calamba City Hall, 31 August 2026. Pooling (Regular na Byahe) is withdrawn as
-- a bookable option, and in exchange the LGU administrator raised the Espesyal
-- passenger cap from the ordinance's printed 3 to an operating 4 -- reasoning
-- that Regular already permits "hanggang apat (4)", so the group size a
-- tricycle carries is unchanged; only the billing basis is. A group of four
-- that would have booked Regular now books Espesyal.
--
-- THE DESIGN PROBLEM THIS MIGRATION SOLVES
--
-- fare_matrix.max_passengers currently holds 3 for 'special'. That 3 is a
-- TRANSCRIPTION of the printed ordinance ("Isa (1) hanggang tatlo (3)
-- lamang"), and 15_lgu_ordinance_743_test.sql asserts it as such. The whole
-- point of that test is that a panelist can photograph the tarpaulin bolted to
-- any Calamba tricycle and check our database against it, row for row.
--
-- Overwriting that 3 with a 4 would quietly make the database disagree with the
-- posted matrix and would turn a passing provenance test into a lie. So the
-- transcribed column is left alone and the operating decision is stored
-- separately. The database now records BOTH facts and can answer both
-- questions:
--
--   "What does Ordinance 743 print?"        -> max_passengers            = 3
--   "What does the LGU let ArangCada do?"   -> operating_max_passengers  = 4
--
-- Test 15 stays green and unmodified. The deviation is visible in the schema
-- rather than hidden in a changed number.
--
-- NO FARE CHANGES. Espesyal is PHP 60.00 kada byahe -- per trip, not per
-- passenger (is_per_passenger = false). One passenger and four passengers pay
-- exactly the same for the same distance. This migration changes a cap, never
-- an amount.

alter table public.fare_matrix
  add column if not exists operating_max_passengers integer;

-- Deliberately NULLABLE, and null is meaningful: it means "no operating
-- override, fall back to the printed ordinance limit". Every read below uses
-- coalesce(operating_max_passengers, max_passengers).
--
-- A not-null column would have been the tidier schema, but supabase/seed.sql
-- re-inserts the fare_matrix rows from scratch on every local test rebuild and
-- runs AFTER migrations. A not-null column with no default breaks that rebuild,
-- and a literal default would silently misdescribe any future ride type. Null-
-- as-"no override" is correct on both paths and needs no default.
alter table public.fare_matrix
  add constraint fare_matrix_operating_max_passengers_range
    check (operating_max_passengers is null
           or (operating_max_passengers >= min_passengers
               and operating_max_passengers <= 4));

comment on column public.fare_matrix.max_passengers is
  'Highest passenger count the ORDINANCE PRINTS. Regular 4, Espesyal 3. '
  'Transcription only -- do not edit to reflect an operating decision. '
  'Pinned by 15_lgu_ordinance_743_test.sql.';
comment on column public.fare_matrix.operating_max_passengers is
  'Highest passenger count ArangCada actually permits. Null means no override: '
  'fall back to the printed max_passengers. May exceed the '
  'printed limit where the LGU has approved it. Espesyal is 4 by the decision '
  'of the Calamba City LGU administrator, 31 Aug 2026, granted in exchange for '
  'withdrawing pooling.';

-- The operating decision itself.
update public.fare_matrix
   set operating_max_passengers = 4
 where ride_type = 'special';

-- Pooling stays in the enum and in this table: its rows are
-- the transcribed record of Regular na Byahe and back the fare-matrix reference
-- screen. It is simply no longer offered as a booking option. Flag it so no
-- future query has to infer bookability from a UI file.
alter table public.fare_matrix
  add column if not exists is_bookable boolean not null default true;

update public.fare_matrix set is_bookable = (ride_type = 'special');

comment on column public.fare_matrix.is_bookable is
  'False for ride types retained as ordinance record but withdrawn from the '
  'commuter booking flow. Pooling (Regular na Byahe) withdrawn 31 Aug 2026 by '
  'Calamba City Hall. Do not drop such rows -- the fare data stays correct and '
  'pinned in case the LGU restores the service.';

-- Passenger count on the trip.
alter table public.trips
  add column if not exists passenger_count integer not null default 1;

alter table public.trips
  add constraint trips_passenger_count_range
    check (passenger_count between 1 and 4);

comment on column public.trips.passenger_count is
  'Passengers on this trip, 1-4. Does not affect an Espesyal fare (per trip, '
  'not per passenger); recorded for capacity, dispatch and LGU reporting.';

-- compute_fare_centavos: validate against the operating cap, not the printed
-- one. Body is otherwise carried over unchanged from
-- 20260729000000_lgu_fare_matrix_ordinance_743.sql; only the bound in the
-- passenger-range guard and its error message move.
create or replace function public.compute_fare_centavos(
  p_distance_m      integer,
  p_ride_type       public.ride_type,
  p_fare_class      public.passenger_fare_class default 'standard',
  p_passenger_count integer default 1
)
returns integer
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_bracket public.fare_matrix%rowtype;
  v_pax     integer := coalesce(p_passenger_count, 1);
  v_unit    integer;
  v_cap     integer;
begin
  if p_distance_m is null or p_ride_type is null or p_fare_class is null then
    return null;
  end if;

  select *
    into v_bracket
    from public.fare_matrix
   where ride_type = p_ride_type
     and is_active
   limit 1;

  if not found then
    raise exception 'compute_fare: no active fare bracket for ride type %', p_ride_type
      using errcode = 'P0002';
  end if;

  -- THE ONLY BEHAVIOURAL CHANGE IN THIS FUNCTION.
  -- Was: v_bracket.max_passengers (the ordinance's printed limit).
  -- Now: the LGU-approved operating cap, falling back to the printed limit
  -- when no override is recorded. Espesyal is therefore 4, not 3.
  -- Everything else below -- the null guards, the P0002 code, the 22023 code,
  -- the per-passenger multiplication -- is carried over verbatim from
  -- 20260729000000_lgu_fare_matrix_ordinance_743.sql.
  v_cap := coalesce(v_bracket.operating_max_passengers, v_bracket.max_passengers);

  if v_pax < v_bracket.min_passengers or v_pax > v_cap then
    raise exception
      'compute_fare: % passengers is outside the % operating limit of %-%',
      v_pax, p_ride_type, v_bracket.min_passengers, v_cap
      using errcode = '22023';
  end if;

  v_unit := public.compute_fare_unit_centavos(p_distance_m, p_ride_type, p_fare_class);

  if v_unit is null then
    return null;
  end if;

  -- Espesyal na Byahe is one price for the vehicle, however many ride in it.
  if not v_bracket.is_per_passenger then
    return v_unit;
  end if;

  return v_unit * v_pax;
end;
$$;

comment on function public.compute_fare_centavos(integer, public.ride_type, public.passenger_fare_class, integer) is
  'Authoritative total in centavos owed by the booking party. Per-passenger ride '
  'types multiply by passenger count; per-trip ride types do not. Rejects '
  'passenger counts outside the LGU-approved operating limits '
  '(fare_matrix.operating_max_passengers), which for Espesyal is 4 rather than '
  'the ordinance''s printed 3.';

-- request_ride: carry the requested passenger count onto the trip.
--
-- Deliberately NOT added as a new function parameter. request_ride's signature
-- is granted, revoked, and referenced by name in three migrations and in the
-- mobile client; changing its arity would break every one of those and force a
-- coordinated client release. Passenger count does not affect an Espesyal fare,
-- so the trip is created at the default of 1 and the commuter's selection is
-- applied through set_trip_passenger_count below, before the driver arrives.
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

  if not found or v_trip.rider_id <> auth.uid() then
    raise exception 'that trip does not belong to you'
      using errcode = '42501';
  end if;

  if v_trip.status not in ('requested', 'searching_driver', 'driver_assigned', 'accepted') then
    raise exception 'passenger count can no longer be changed on this trip'
      using errcode = '22023';
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

comment on function public.set_trip_passenger_count(uuid, integer) is
  'Sets passenger count on the caller''s own trip, bounded server-side by '
  'fare_matrix.operating_max_passengers. Does not change an Espesyal fare.';

revoke execute on function public.set_trip_passenger_count(uuid, integer)
  from public, anon;
grant execute on function public.set_trip_passenger_count(uuid, integer)
  to authenticated, service_role;
