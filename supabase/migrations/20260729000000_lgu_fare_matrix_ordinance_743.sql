-- Align the fare surface with Calamba City Ordinance No. 743, Series of 2022.
--
-- The seeded rates until now were invented stand-ins. The real matrix is posted
-- on every franchised tricycle in Calamba (BPTFO "Minimum Fare Matrix"), and it
-- differs from the placeholders structurally, not just numerically:
--
--   1. The base bracket is the first TWO kilometres, not the first one.
--   2. There is a second fare column for Senior Citizens, PWDs, and students.
--   3. "Regular na Byahe" is billed PER PASSENGER (max 4); "Espesyal na Byahe"
--      is billed PER TRIP (1-3 passengers).
--
-- This migration adds the schema those three facts require. The amounts
-- themselves stay in supabase/seed.sql: LGU fares change by ordinance, so they
-- should be a data change an admin can make and an auditor can trace, not a
-- code deploy.
--
-- Terminology note: the codebase enum value 'pooling' IS the ordinance's
-- "Regular na Byahe" -- a shared ride billed per passenger. The enum is left
-- alone on purpose (CLAUDE.md rule 6 fixes the booking types as special and
-- pooling); see docs/LGU_FARE_MATRIX.md for the mapping.

-- ---------------------------------------------------------------------------
-- Fare class
-- ---------------------------------------------------------------------------
-- Named passenger_fare_class rather than "fare_category" because the ordinance
-- already uses the word "Regular" for a *ride type*. Two meanings of "regular"
-- in one fare module is how someone eventually charges a senior citizen the
-- wrong amount.
create type public.passenger_fare_class as enum ('standard', 'discounted');

comment on type public.passenger_fare_class is
  'standard = full fare. discounted = Senior Citizen / PWD / student column of '
  'the posted LGU matrix (statutory 20%, but the printed amounts govern).';

-- ---------------------------------------------------------------------------
-- fare_matrix: ordinance metadata and passenger rules
-- ---------------------------------------------------------------------------
alter table public.fare_matrix
  add column discount_per_km_centavos integer  not null default 0,
  add column min_passengers           integer  not null default 1,
  add column max_passengers           integer  not null default 1,
  add column is_per_passenger         boolean  not null default false,
  add column ordinance_ref            text,
  add column printed_max_km           integer;

alter table public.fare_matrix
  add constraint fare_matrix_discount_per_km_nonneg
    check (discount_per_km_centavos >= 0),
  add constraint fare_matrix_min_passengers_positive
    check (min_passengers >= 1),
  add constraint fare_matrix_passenger_range
    check (max_passengers >= min_passengers),
  -- A printed table that stops before the base bracket would make the
  -- extrapolation branch unreachable and the bracket rows meaningless.
  add constraint fare_matrix_printed_max_km_covers_base
    check (printed_max_km is null or printed_max_km * 1000 >= base_distance_m);

comment on column public.fare_matrix.discount_per_km_centavos is
  'Discounted charge per started kilometre BEYOND the printed table. Inside the '
  'printed range the fare_discount_brackets rows govern, not this rate.';
comment on column public.fare_matrix.min_passengers is
  'Lowest passenger count the ordinance permits for this ride type.';
comment on column public.fare_matrix.max_passengers is
  'Highest passenger count the ordinance permits. Regular 4, Espesyal 3.';
comment on column public.fare_matrix.is_per_passenger is
  'True when the printed amount is owed by EACH passenger (Regular na Byahe). '
  'False when it is owed once for the whole trip (Espesyal na Byahe).';
comment on column public.fare_matrix.ordinance_ref is
  'Citation for the posted matrix these rates were transcribed from.';
comment on column public.fare_matrix.printed_max_km is
  'Last kilometre row printed on the tarpaulin. Past it, fares extrapolate from '
  'the per-km rates and that fact is disclosed rather than hidden.';

-- ---------------------------------------------------------------------------
-- fare_discount_brackets: the discounted column, transcribed verbatim
-- ---------------------------------------------------------------------------
-- Deliberately NOT computed as "20% off, rounded". Two of the nineteen printed
-- regular-fare rows do not follow any consistent rounding rule (4 km prints
-- P15.50 where 20% yields P15.20; 16 km prints P34.00 where 20% yields P34.40).
-- A formula would quietly disagree with the tarpaulin a passenger can point at,
-- and the tarpaulin is what the LGU enforces. So the printed numbers are the
-- data, and this table can be checked against the photo row for row.
create table public.fare_discount_brackets (
  id             uuid primary key default gen_random_uuid(),
  fare_matrix_id uuid    not null references public.fare_matrix (id) on delete cascade,
  km             integer not null,
  fare_centavos  integer not null,
  created_at     timestamptz not null default now(),
  constraint fare_discount_brackets_km_positive check (km >= 1),
  constraint fare_discount_brackets_fare_nonneg check (fare_centavos >= 0),
  constraint fare_discount_brackets_unique_row unique (fare_matrix_id, km)
);

comment on table public.fare_discount_brackets is
  'Senior Citizen / PWD / student amounts exactly as printed on the LGU fare '
  'matrix. km is the printed row: 2 is the "First 2km" row.';
comment on column public.fare_discount_brackets.km is
  'Printed kilometre row. A trip billing k started kilometres reads row k.';

create index fare_discount_brackets_lookup_idx
  on public.fare_discount_brackets (fare_matrix_id, km);

alter table public.fare_discount_brackets enable row level security;

-- Reference data: this table is literally posted in public on every tricycle,
-- so authenticated read is correct. Writes stay admin-only, matching
-- fare_matrix_admin_write.
create policy fare_discount_brackets_select_authenticated
  on public.fare_discount_brackets for select
  to authenticated
  using (
    exists (
      select 1
        from public.fare_matrix fm
       where fm.id = fare_discount_brackets.fare_matrix_id
         and fm.is_active
    )
  );

create policy fare_discount_brackets_admin_write
  on public.fare_discount_brackets for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ---------------------------------------------------------------------------
-- Which printed row does a distance fall in?
-- ---------------------------------------------------------------------------
create or replace function public.fare_chargeable_km(
  p_distance_m      integer,
  p_base_distance_m integer
)
returns integer
language sql
immutable
as $$
  -- The base bracket occupies the first ceil(base/1000) rows of the printed
  -- table ("First 2km"). Past it, each started kilometre advances one row.
  select case
           when p_distance_m is null or p_base_distance_m is null then null
           when p_distance_m <= p_base_distance_m
             then ((p_base_distance_m + 999) / 1000)::integer
           else ((p_base_distance_m + 999) / 1000)::integer
                + public.fare_km_increments(p_distance_m - p_base_distance_m)
         end;
$$;

comment on function public.fare_chargeable_km(integer, integer) is
  'Printed matrix row for a distance. Everything inside the base bracket reads '
  'the first row; any started kilometre past it advances one row.';

-- ---------------------------------------------------------------------------
-- Unit fare: what ONE billable unit costs
-- ---------------------------------------------------------------------------
-- For Regular na Byahe a unit is one passenger; for Espesyal na Byahe a unit is
-- the whole trip. Kept separate from the total so the UI can show "P17.00 x 3"
-- instead of an unexplained lump sum.
--
-- security definer: a fare must be computable even though both fare tables are
-- RLS-protected. search_path is pinned so the definer right cannot be
-- redirected to an attacker-controlled schema.
create or replace function public.compute_fare_unit_centavos(
  p_distance_m integer,
  p_ride_type  public.ride_type,
  p_fare_class public.passenger_fare_class default 'standard'
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bracket   public.fare_matrix%rowtype;
  v_km        integer;
  v_printed   integer;
  v_last_row  integer;
begin
  -- Unknown input yields null rather than a bogus charge.
  if p_distance_m is null or p_ride_type is null or p_fare_class is null then
    return null;
  end if;

  if p_distance_m < 0 then
    raise exception 'compute_fare: distance_m must not be negative (got %)', p_distance_m
      using errcode = '22023';
  end if;

  select *
    into v_bracket
    from public.fare_matrix
   where ride_type = p_ride_type
     and is_active
   limit 1;

  -- Refuse to invent a price. Silently falling back to a default would
  -- undercharge or overcharge a real passenger.
  if not found then
    raise exception 'compute_fare: no active fare bracket for ride type %', p_ride_type
      using errcode = 'P0002';
  end if;

  if p_fare_class = 'standard' then
    return v_bracket.base_fare_centavos
         + public.fare_km_increments(p_distance_m - v_bracket.base_distance_m)
           * v_bracket.per_km_centavos;
  end if;

  -- Discounted: the printed column governs wherever it exists.
  v_km := public.fare_chargeable_km(p_distance_m, v_bracket.base_distance_m);

  select fare_centavos
    into v_printed
    from public.fare_discount_brackets
   where fare_matrix_id = v_bracket.id
     and km = v_km;

  if found then
    return v_printed;
  end if;

  -- Past the end of the printed table. Extrapolate from the last printed row
  -- using the discounted per-km rate -- but only if the matrix actually
  -- declares where its printed range ends and has a row there.
  if v_bracket.printed_max_km is null or v_km <= v_bracket.printed_max_km then
    raise exception
      'compute_fare: no discounted bracket for ride type % at % km', p_ride_type, v_km
      using errcode = 'P0002';
  end if;

  select fare_centavos
    into v_last_row
    from public.fare_discount_brackets
   where fare_matrix_id = v_bracket.id
     and km = v_bracket.printed_max_km;

  if not found then
    raise exception
      'compute_fare: discounted bracket table for ride type % is missing its last printed row (% km)',
      p_ride_type, v_bracket.printed_max_km
      using errcode = 'P0002';
  end if;

  return v_last_row
       + (v_km - v_bracket.printed_max_km) * v_bracket.discount_per_km_centavos;
end;
$$;

comment on function public.compute_fare_unit_centavos(integer, public.ride_type, public.passenger_fare_class) is
  'Cost of one billable unit in centavos: one passenger for Regular na Byahe, '
  'one trip for Espesyal na Byahe.';

-- ---------------------------------------------------------------------------
-- Total fare owed by the booking party
-- ---------------------------------------------------------------------------
-- The 2-argument forms are dropped rather than overloaded: leaving them beside
-- the new defaulted signatures would make compute_fare(1000, 'special')
-- ambiguous and fail to resolve.
drop function if exists public.compute_fare(integer, public.ride_type);
drop function if exists public.compute_fare_centavos(integer, public.ride_type);

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
set search_path = public
as $$
declare
  v_bracket public.fare_matrix%rowtype;
  v_pax     integer := coalesce(p_passenger_count, 1);
  v_unit    integer;
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

  -- The ordinance caps party size per ride type (Regular 4, Espesyal 3).
  -- Enforced here because this is the trusted path; a client-side check would
  -- only be a convenience.
  if v_pax < v_bracket.min_passengers or v_pax > v_bracket.max_passengers then
    raise exception
      'compute_fare: % passengers is outside the % ordinance limit of %-%',
      v_pax, p_ride_type, v_bracket.min_passengers, v_bracket.max_passengers
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
  'passenger counts outside the ordinance limits.';

create or replace function public.compute_fare(
  p_distance_m      integer,
  p_ride_type       public.ride_type,
  p_fare_class      public.passenger_fare_class default 'standard',
  p_passenger_count integer default 1
)
returns numeric
language sql
stable
as $$
  select public.compute_fare_centavos(
           p_distance_m, p_ride_type, p_fare_class, p_passenger_count
         )::numeric / 100;
$$;

comment on function public.compute_fare(integer, public.ride_type, public.passenger_fare_class, integer) is
  'Authoritative total fare in pesos under Calamba City Ordinance No. 743, '
  's. 2022. Thin wrapper over compute_fare_centavos.';
