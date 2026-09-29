-- pgTAP: fare computation.
--
-- Final fare is trusted server-side logic: the client may preview a fare, but
-- the authoritative figure must come from the database. These tests
-- pin the bracket-boundary behaviour so a later refactor cannot silently shift
-- what a passenger is charged.
--
-- Fare rule under test
--   base_fare covers the first base_distance_m metres.
--   Every *started* kilometre beyond that adds one full per_km increment.
--   So the charge steps up at 1 metre past each kilometre mark, not at the mark
--   itself. The boundary cases below are the whole point of this file.
--
-- Seeded brackets (supabase/seed.sql), from Calamba City Ordinance No. 743,
-- s. 2022. Note the base bracket is the first TWO kilometres:
--   special  "Espesyal na Byahe"  base P60.00 / first 2000 m, +P8.00 per started km
--   pooling  "Regular na Byahe"   base P15.00 / first 2000 m, +P2.00 per started km
--
-- Conformance of every printed row to the posted matrix lives in
-- 15_lgu_ordinance_743_test.sql. This file is about the rounding contract.

begin;

select plan(20);

-- ---------------------------------------------------------------------------
-- Existence
-- ---------------------------------------------------------------------------
select has_function(
  'public', 'compute_fare',
  'compute_fare() should exist in the public schema'
);

-- ---------------------------------------------------------------------------
-- Special — base bracket (now the first 2 km, not the first 1 km)
-- ---------------------------------------------------------------------------
select is(public.compute_fare(0, 'special'), 60.00::numeric,
  'special: a zero-distance trip still owes the base fare');

select is(public.compute_fare(1999, 'special'), 60.00::numeric,
  'special: 1999 m is inside the base bracket');

select is(public.compute_fare(2000, 'special'), 60.00::numeric,
  'special: exactly 2000 m is the LAST metre of the base bracket, not the first '
  'metre of the next one');

-- ---------------------------------------------------------------------------
-- Special — bracket boundaries (the rounding contract)
-- ---------------------------------------------------------------------------
select is(public.compute_fare(2001, 'special'), 68.00::numeric,
  'special: 2001 m starts the 3rd km and bills a full increment');

select is(public.compute_fare(2500, 'special'), 68.00::numeric,
  'special: a part-used 3rd km bills the same as a fully used one');

select is(public.compute_fare(3000, 'special'), 68.00::numeric,
  'special: exactly 3000 m is still one increment');

select is(public.compute_fare(3001, 'special'), 76.00::numeric,
  'special: 3001 m tips into the 4th km');

select is(public.compute_fare(4000, 'special'), 76.00::numeric,
  'special: exactly 4000 m is still two increments');

select is(public.compute_fare(10000, 'special'), 124.00::numeric,
  'special: 10 km = base + 8 increments');

-- ---------------------------------------------------------------------------
-- Pooling — same rounding rule, cheaper rates
-- ---------------------------------------------------------------------------
select is(public.compute_fare(0, 'pooling'), 15.00::numeric,
  'pooling: zero distance owes the pooling base fare');

select is(public.compute_fare(2000, 'pooling'), 15.00::numeric,
  'pooling: exactly 2000 m is the last metre of the base bracket');

select is(public.compute_fare(2001, 'pooling'), 17.00::numeric,
  'pooling: 2001 m starts the 3rd km');

select is(public.compute_fare(3000, 'pooling'), 17.00::numeric,
  'pooling: exactly 3000 m is still one increment');

select is(public.compute_fare(3001, 'pooling'), 19.00::numeric,
  'pooling: 3001 m tips into the 4th km');

select is(public.compute_fare(5000, 'pooling'), 21.00::numeric,
  'pooling: 5 km = base + 3 increments');

-- ---------------------------------------------------------------------------
-- Cross-type invariant
-- ---------------------------------------------------------------------------
select cmp_ok(
  public.compute_fare(4000, 'pooling'), '<', public.compute_fare(4000, 'special'),
  'pooling must never cost more than special for the same distance'
);

-- ---------------------------------------------------------------------------
-- Defaulted arguments
-- ---------------------------------------------------------------------------
-- The signature grew a fare class and a passenger count. A two-argument call
-- must still mean "one standard-fare passenger", or every existing call site
-- silently changes meaning.
select is(
  public.compute_fare(3000, 'special'),
  public.compute_fare(3000, 'special', 'standard', 1),
  'a two-argument call defaults to one standard-fare passenger'
);

-- ---------------------------------------------------------------------------
-- Defensive input handling
-- ---------------------------------------------------------------------------
select is(public.compute_fare(null, 'special'), null::numeric,
  'unknown distance yields null rather than a bogus charge');

select throws_ok(
  $$ select public.compute_fare(-1, 'special') $$,
  '22023',
  null,
  'a negative distance is rejected instead of silently charging the base fare'
);

select * from finish();

rollback;
