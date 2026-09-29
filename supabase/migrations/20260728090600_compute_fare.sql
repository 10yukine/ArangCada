-- Trusted fare computation.
--
-- The client may show a fare preview, but this function is the authority
-- (final fare comes from an Edge Function or a locked database function).
-- No surge pricing: fare is a pure function of distance and ride
-- type.
--
-- Rule: base_fare covers the first base_distance_m metres; every *started*
-- kilometre beyond that adds one full per_km increment.

create or replace function public.compute_fare(
  p_distance_m integer,
  p_ride_type  public.ride_type
)
returns numeric
language plpgsql
immutable
as $$
declare
  v_base_fare       numeric;
  v_base_distance_m integer;
  v_per_km          numeric;
  v_extra_m         integer;
  v_increments      integer;
begin
  if p_distance_m is null or p_ride_type is null then
    return null;
  end if;

  if p_distance_m < 0 then
    raise exception 'compute_fare: distance_m must not be negative (got %)', p_distance_m
      using errcode = '22023';
  end if;

  -- NOTE: hardcoded on purpose at this step. These are LGU-set rates that
  -- change by ordinance, so they do not belong in a function body -- the very
  -- next migration moves them into fare_matrix.
  if p_ride_type = 'special' then
    v_base_fare       := 25.00;
    v_base_distance_m := 1000;
    v_per_km          := 8.00;
  else
    v_base_fare       := 15.00;
    v_base_distance_m := 1000;
    v_per_km          := 5.00;
  end if;

  v_extra_m := p_distance_m - v_base_distance_m;

  -- Inside the base bracket, including exactly on the boundary metre.
  if v_extra_m <= 0 then
    return v_base_fare;
  end if;

  -- Any fraction of a kilometre bills as a whole one.
  v_increments := ceil(v_extra_m::numeric / 1000.0);

  return v_base_fare + (v_increments * v_per_km);
end;
$$;

comment on function public.compute_fare(integer, public.ride_type) is
  'Authoritative distance-based fare. Each started kilometre past the base '
  'bracket bills in full. Returns null for unknown distance; rejects negatives.';
