-- pgTAP: surface introduced by the fare_matrix / centavos refactor.
--
-- 10_compute_fare_test.sql is deliberately left untouched by that refactor --
-- it is the evidence that externalising the rates did not change what a
-- passenger is charged. This file covers only what is genuinely new: the
-- extracted rounding helper, the centavos-denominated core, and the failure
-- mode that only becomes possible once rates live in a table.

begin;

select plan(12);

-- ---------------------------------------------------------------------------
-- Extracted rounding helper
-- ---------------------------------------------------------------------------
select has_function(
  'public', 'fare_km_increments',
  'fare_km_increments() should exist'
);

select is(public.fare_km_increments(0), 0,
  'no distance past the base bracket bills no increments');

select is(public.fare_km_increments(1), 1,
  'a single metre past the base bracket bills a whole kilometre');

select is(public.fare_km_increments(999), 1,
  '999 m past base is still one started kilometre');

select is(public.fare_km_increments(1000), 1,
  'exactly 1000 m past base is one kilometre, not two');

select is(public.fare_km_increments(1001), 2,
  '1001 m past base starts a second kilometre');

select is(public.fare_km_increments(null), null::integer,
  'null distance propagates rather than counting as zero');

-- ---------------------------------------------------------------------------
-- Centavos core
-- ---------------------------------------------------------------------------
select has_function(
  'public', 'compute_fare_centavos',
  'compute_fare_centavos() should exist'
);

select is(public.compute_fare_centavos(1000, 'special'), 2500,
  'special base bracket is 2500 centavos');

select is(public.compute_fare_centavos(1001, 'special'), 3300,
  'special with one increment is 3300 centavos');

select is(public.compute_fare_centavos(2001, 'pooling'), 2500,
  'pooling with two increments is 2500 centavos');

-- ---------------------------------------------------------------------------
-- New failure mode: rates now come from data, so they can be missing.
-- ---------------------------------------------------------------------------
update public.fare_matrix set is_active = false where ride_type = 'special';

select throws_ok(
  $$ select public.compute_fare_centavos(1500, 'special') $$,
  'P0002',
  null,
  'with no active bracket the fare is refused, not guessed from a default'
);

select * from finish();

rollback;
