-- Refactor: compute_fare reads its rates from fare_matrix instead of carrying
-- them in its body, and does its arithmetic in integer centavos.
--
-- Behaviour is unchanged -- supabase/tests/10_compute_fare_test.sql is not
-- modified by this migration and must still pass untouched.
--
-- Why this matters beyond tidiness: LGU fares change by ordinance. With the
-- rates in the table, updating them is a data change an admin can make and an
-- auditor can see, not a code deploy.

-- ---------------------------------------------------------------------------
-- Rounding helper, extracted so the "started kilometre" rule lives in exactly
-- one place and can be tested on its own.
-- ---------------------------------------------------------------------------
create or replace function public.fare_km_increments(p_extra_m integer)
returns integer
language sql
immutable
as $$
  -- Integer ceiling division: any fraction of a kilometre counts as a whole.
  select case
           when p_extra_m is null then null
           when p_extra_m <= 0    then 0
           else ((p_extra_m + 999) / 1000)::integer
         end;
$$;

comment on function public.fare_km_increments(integer) is
  'Number of chargeable kilometres for a distance past the base bracket. '
  'Any started kilometre counts in full.';

-- ---------------------------------------------------------------------------
-- Core computation, in centavos.
-- ---------------------------------------------------------------------------
-- security definer: a fare must be computable even though fare_matrix is
-- RLS-protected. search_path is pinned so the definer right cannot be
-- redirected to an attacker-controlled schema.
create or replace function public.compute_fare_centavos(
  p_distance_m integer,
  p_ride_type  public.ride_type
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_bracket public.fare_matrix%rowtype;
  v_extra_m integer;
begin
  if p_distance_m is null or p_ride_type is null then
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

  v_extra_m := p_distance_m - v_bracket.base_distance_m;

  return v_bracket.base_fare_centavos
       + public.fare_km_increments(v_extra_m) * v_bracket.per_km_centavos;
end;
$$;

comment on function public.compute_fare_centavos(integer, public.ride_type) is
  'Authoritative fare in centavos, with rates read from fare_matrix.';

-- ---------------------------------------------------------------------------
-- Peso-denominated wrapper. Preserves the original contract so existing
-- callers and the original test suite are unaffected.
-- ---------------------------------------------------------------------------
create or replace function public.compute_fare(
  p_distance_m integer,
  p_ride_type  public.ride_type
)
returns numeric
language sql
stable
as $$
  select public.compute_fare_centavos(p_distance_m, p_ride_type)::numeric / 100;
$$;

comment on function public.compute_fare(integer, public.ride_type) is
  'Authoritative distance-based fare in pesos. Thin wrapper over '
  'compute_fare_centavos; rates come from fare_matrix.';
