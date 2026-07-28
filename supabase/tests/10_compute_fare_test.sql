-- pgTAP: fare computation.
--
-- Final fare is trusted server-side logic (CLAUDE.md: the client may preview a
-- fare, but the authoritative figure must come from the database). These tests
-- pin the bracket-boundary behaviour so a later refactor cannot silently shift
-- what a passenger is charged.
--
-- Fare rule under test
--   base_fare covers the first base_distance_m metres.
--   Every *started* kilometre beyond that adds one full per_km increment.
--   So the charge steps up at 1 metre past each kilometre mark, not at the mark
--   itself. The boundary cases below are the whole point of this file.
--
-- Seeded brackets (supabase/seed.sql):
--   special  base P25.00 / first 1000 m, +P8.00 per started km
--   pooling  base P15.00 / first 1000 m, +P5.00 per started km

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
-- Special — base bracket
-- ---------------------------------------------------------------------------
select is(public.compute_fare(0, 'special'), 25.00::numeric,
  'special: a zero-distance trip still owes the base fare');

select is(public.compute_fare(999, 'special'), 25.00::numeric,
  'special: 999 m is inside the base bracket');

select is(public.compute_fare(1000, 'special'), 25.00::numeric,
  'special: exactly 1000 m is the LAST metre of the base bracket, not the first '
  'metre of the next one');

-- ---------------------------------------------------------------------------
-- Special — bracket boundaries (the rounding contract)
-- ---------------------------------------------------------------------------
select is(public.compute_fare(1001, 'special'), 33.00::numeric,
  'special: 1001 m starts the 2nd km and bills a full increment');

select is(public.compute_fare(1500, 'special'), 33.00::numeric,
  'special: a part-used 2nd km bills the same as a fully used one');

select is(public.compute_fare(2000, 'special'), 33.00::numeric,
  'special: exactly 2000 m is still one increment');

select is(public.compute_fare(2001, 'special'), 41.00::numeric,
  'special: 2001 m tips into the 3rd km');

select is(public.compute_fare(3000, 'special'), 41.00::numeric,
  'special: exactly 3000 m is still two increments');

select is(public.compute_fare(3001, 'special'), 49.00::numeric,
  'special: 3001 m tips into the 4th km');

select is(public.compute_fare(10000, 'special'), 97.00::numeric,
  'special: 10 km = base + 9 increments');

-- ---------------------------------------------------------------------------
-- Pooling — same rounding rule, cheaper rates
-- ---------------------------------------------------------------------------
select is(public.compute_fare(0, 'pooling'), 15.00::numeric,
  'pooling: zero distance owes the pooling base fare');

select is(public.compute_fare(1000, 'pooling'), 15.00::numeric,
  'pooling: exactly 1000 m is the last metre of the base bracket');

select is(public.compute_fare(1001, 'pooling'), 20.00::numeric,
  'pooling: 1001 m starts the 2nd km');

select is(public.compute_fare(2000, 'pooling'), 20.00::numeric,
  'pooling: exactly 2000 m is still one increment');

select is(public.compute_fare(2001, 'pooling'), 25.00::numeric,
  'pooling: 2001 m tips into the 3rd km');

select is(public.compute_fare(5000, 'pooling'), 35.00::numeric,
  'pooling: 5 km = base + 4 increments');

-- ---------------------------------------------------------------------------
-- Cross-type invariant
-- ---------------------------------------------------------------------------
select cmp_ok(
  public.compute_fare(3000, 'pooling'), '<', public.compute_fare(3000, 'special'),
  'pooling must never cost more than special for the same distance'
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
