-- pgTAP: the helper surface underneath compute_fare().
--
-- 10_compute_fare_test.sql covers the rounding contract and
-- 15_lgu_ordinance_743_test.sql covers conformance with the posted matrix.
-- This file covers the pieces those two lean on: the started-kilometre helper,
-- the printed-row resolver, the centavos-denominated core, and the failure
-- modes that only exist because the rates live in tables.

begin;

select plan(22);

-- ---------------------------------------------------------------------------
-- Started-kilometre helper
-- ---------------------------------------------------------------------------
-- Rate-independent: these assertions held before Ordinance 743 was transcribed
-- and must keep holding after, because the rule is about counting kilometres,
-- not about pricing them.

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
-- Printed-row resolver
-- ---------------------------------------------------------------------------
-- Maps a distance onto a row of the published matrix. The base bracket spans
-- the first two kilometres, so everything up to 2000 m reads the "First 2km"
-- row and the table only starts advancing after that.

select has_function(
  'public', 'fare_chargeable_km',
  'fare_chargeable_km() should exist'
);

select is(public.fare_chargeable_km(0, 2000), 2,
  'a zero-distance trip reads the "First 2km" row');

select is(public.fare_chargeable_km(2000, 2000), 2,
  'exactly 2000 m still reads the "First 2km" row');

select is(public.fare_chargeable_km(2001, 2000), 3,
  '2001 m advances to the 3 km row');

select is(public.fare_chargeable_km(3000, 2000), 3,
  'exactly 3000 m is still the 3 km row');

select is(public.fare_chargeable_km(20001, 2000), 21,
  '20001 m lands one row past the end of the published table');

-- ---------------------------------------------------------------------------
-- Centavos core
-- ---------------------------------------------------------------------------
-- Money in a fare table is counted, not measured. The integer core is what the
-- peso wrapper divides down from.

select has_function(
  'public', 'compute_fare_centavos',
  'compute_fare_centavos() should exist'
);

select is(public.compute_fare_centavos(2000, 'special'), 6000,
  'special base bracket is 6000 centavos');

select is(public.compute_fare_centavos(2001, 'special'), 6800,
  'special with one increment is 6800 centavos');

select is(public.compute_fare_centavos(3001, 'pooling'), 1900,
  'pooling with two increments is 1900 centavos');

-- ---------------------------------------------------------------------------
-- Unit fare
-- ---------------------------------------------------------------------------
-- Exposed separately so a fare breakdown can show "P17.00 x 3" rather than an
-- unexplained lump sum.

select has_function(
  'public', 'compute_fare_unit_centavos',
  'compute_fare_unit_centavos() should exist'
);

select is(public.compute_fare_unit_centavos(3000, 'pooling', 'discounted'), 1350,
  'the unit fare is the per-passenger amount before any multiplication');

select is(
  public.compute_fare_centavos(3000, 'pooling', 'discounted', 3),
  public.compute_fare_unit_centavos(3000, 'pooling', 'discounted') * 3,
  'the party total is exactly the unit fare times the passenger count'
);

-- ---------------------------------------------------------------------------
-- Failure modes that only exist because rates come from data
-- ---------------------------------------------------------------------------
-- A missing row must refuse to price the trip. Guessing would mean charging a
-- real passenger an amount no ordinance authorises.

delete from public.fare_discount_brackets
 where km = 5
   and fare_matrix_id = (
     select id from public.fare_matrix where ride_type = 'pooling' and is_active
   );

select throws_ok(
  $$ select public.compute_fare_unit_centavos(5000, 'pooling', 'discounted') $$,
  'P0002',
  null,
  'a gap inside the published discount table is refused, not interpolated'
);

update public.fare_matrix set is_active = false where ride_type = 'special';

select throws_ok(
  $$ select public.compute_fare_centavos(1500, 'special') $$,
  'P0002',
  null,
  'with no active bracket the fare is refused, not guessed from a default'
);

select * from finish();

rollback;
