-- pgTAP: conformance with the posted Calamba fare matrix.
--
-- This file is the evidence that the database agrees with the matrix posted on
-- every franchised tricycle in the city. 10_compute_fare_test.sql pins the
-- *rounding rule*; this one pins the *numbers*, all seventy-six of them.
--
-- Source: Calamba City BPTFO "TRICYCLE MINIMUM FARE" issuance, City Ordinance
-- 743, Series of 2022. Transcribed from the official BPTFO infographic set and
-- cross-checked against a unit-posted tarpaulin photographed 23 August 2025.
-- Full transcription and provenance in docs/LGU_FARE_MATRIX.md.
--
-- The expected values below are written as literal tables on purpose. They are
-- meant to be diffed against the published matrix by a human, row for row,
-- without having to reason about any formula.
--
-- Ride type mapping:
--   pooling = "Regular na Byahe"  (P15.00 kada pasahero, max 4)
--   special = "Espesyal na Byahe" (P60.00 kada byahe, 1-3 pasahero)

begin;

select plan(22);

-- ---------------------------------------------------------------------------
-- REGULAR NA PAMASAHE — the printed table, row for row
-- ---------------------------------------------------------------------------
-- Row k is asserted at exactly k * 1000 m, which under the started-kilometre
-- rule is the last metre that still bills row k.

select results_eq(
  $$
    select k, public.compute_fare(k * 1000, 'pooling'::public.ride_type)
      from generate_series(2, 20) as k
     order by k
  $$,
  $$
    values (2, 15.00::numeric), (3, 17.00), (4, 19.00), (5, 21.00), (6, 23.00),
           (7, 25.00), (8, 27.00), (9, 29.00), (10, 31.00), (11, 33.00),
           (12, 35.00), (13, 37.00), (14, 39.00), (15, 41.00), (16, 43.00),
           (17, 45.00), (18, 47.00), (19, 49.00), (20, 51.00)
  $$,
  'Regular na Byahe: minimum na pamasahe PER PASSENGER matches the posted matrix, 2-20 km'
);

select results_eq(
  $$
    select k, public.compute_fare(k * 1000, 'pooling'::public.ride_type, 'discounted')
      from generate_series(2, 20) as k
     order by k
  $$,
  $$
    values (2, 12.00::numeric), (3, 13.50), (4, 15.50), (5, 17.00), (6, 18.50),
           (7, 20.00), (8, 22.00), (9, 23.00), (10, 25.00), (11, 26.50),
           (12, 28.00), (13, 30.00), (14, 31.50), (15, 33.00), (16, 34.00),
           (17, 36.00), (18, 37.50), (19, 39.00), (20, 41.00)
  $$,
  'Regular na Byahe: Senior Citizen / PWD / Estudyante column matches the posted '
  'matrix verbatim, including the 4 km and 16 km rows that do not follow a clean '
  '20% rounding'
);

-- ---------------------------------------------------------------------------
-- ESPESYAL NA BYAHE O EXTRA — the printed table, row for row
-- ---------------------------------------------------------------------------
select results_eq(
  $$
    select k, public.compute_fare(k * 1000, 'special'::public.ride_type)
      from generate_series(2, 20) as k
     order by k
  $$,
  $$
    values (2, 60.00::numeric), (3, 68.00), (4, 76.00), (5, 84.00), (6, 92.00),
           (7, 100.00), (8, 108.00), (9, 116.00), (10, 124.00), (11, 132.00),
           (12, 140.00), (13, 148.00), (14, 156.00), (15, 164.00), (16, 172.00),
           (17, 180.00), (18, 188.00), (19, 196.00), (20, 204.00)
  $$,
  'Espesyal na Byahe: minimum na pamasahe PER BYAHE matches the posted matrix, 2-20 km'
);

select results_eq(
  $$
    select k, public.compute_fare(k * 1000, 'special'::public.ride_type, 'discounted')
      from generate_series(2, 20) as k
     order by k
  $$,
  $$
    values (2, 48.00::numeric), (3, 54.00), (4, 61.00), (5, 67.00), (6, 74.00),
           (7, 80.00), (8, 86.00), (9, 93.00), (10, 99.00), (11, 106.00),
           (12, 112.00), (13, 118.00), (14, 125.00), (15, 131.00), (16, 138.00),
           (17, 144.00), (18, 150.00), (19, 157.00), (20, 163.00)
  $$,
  'Espesyal na Byahe: Senior Citizen / PWD / Estudyante column matches the posted '
  'matrix verbatim'
);

-- ---------------------------------------------------------------------------
-- Statutory sanity
-- ---------------------------------------------------------------------------
select is_empty(
  $$
    select k, rt
      from generate_series(2, 20) as k
     cross join (values ('special'::public.ride_type), ('pooling')) as t (rt)
     where public.compute_fare(k * 1000, rt, 'discounted')
        >= public.compute_fare(k * 1000, rt, 'standard')
  $$,
  'a discounted passenger is never charged at or above the full fare, at any '
  'printed distance, for either ride type'
);

-- ---------------------------------------------------------------------------
-- The discounted column obeys the same started-kilometre rule
-- ---------------------------------------------------------------------------
select is(public.compute_fare(2001, 'pooling', 'discounted'), 13.50::numeric,
  'discounted pooling: 2001 m reads the 3 km row, not the base row');

select is(public.compute_fare(2001, 'special', 'discounted'), 54.00::numeric,
  'discounted special: 2001 m reads the 3 km row, not the base row');

-- ---------------------------------------------------------------------------
-- Kada pasahero vs kada byahe
-- ---------------------------------------------------------------------------
-- This is the distinction that makes the two halves of the ordinance mean
-- different things, and the easiest one to get wrong.

select is(public.compute_fare(3000, 'pooling', 'standard', 1), 17.00::numeric,
  'Regular na Byahe: one passenger owes one printed fare');

select is(public.compute_fare(3000, 'pooling', 'standard', 4), 68.00::numeric,
  'Regular na Byahe is KADA PASAHERO: four passengers owe four printed fares');

select is(public.compute_fare(3000, 'special', 'standard', 1), 68.00::numeric,
  'Espesyal na Byahe: one passenger owes the trip fare');

select is(public.compute_fare(3000, 'special', 'standard', 3), 68.00::numeric,
  'Espesyal na Byahe is KADA BYAHE: three passengers owe the same as one');

-- ---------------------------------------------------------------------------
-- Passenger limits printed on the BPTFO cards
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select public.compute_fare(3000, 'pooling', 'standard', 5) $$,
  '22023',
  null,
  'Regular na Byahe is capped at APAT (4) na pasahero'
);

-- REVISED 31 August 2026 (Calamba City Hall).
--
-- This assertion used to read "Espesyal na Byahe is capped at TATLO (3) na
-- pasahero" and expected 4 passengers to be REJECTED. The LGU administrator
-- raised the operating cap to 4 when pooling was withdrawn, so 4 must now be
-- accepted. See docs/LGU_FARE_MATRIX.md section 2a.
--
-- The ordinance transcription itself was NOT touched: the assertion further
-- down still pins fare_matrix.max_passengers at 3 for Espesyal, because that is
-- what the posted matrix prints. This file therefore now asserts both facts
-- separately -- what the tarpaulin says, and what the LGU permits us to do --
-- which is exactly the distinction the schema was changed to express.
select lives_ok(
  $$ select public.compute_fare(3000, 'special', 'standard', 4) $$,
  'Espesyal na Byahe accepts APAT (4) na pasahero under the LGU operating cap '
  'approved 31 Aug 2026, even though the printed matrix says tatlo (3)'
);

select is(
  public.compute_fare_centavos(3000, 'special', 'standard', 4),
  public.compute_fare_centavos(3000, 'special', 'standard', 1),
  'the 4th passenger costs nothing extra -- Espesyal is billed kada byahe, so '
  'raising the cap moved no fare'
);

select throws_ok(
  $$ select public.compute_fare(3000, 'special', 'standard', 5) $$,
  '22023',
  null,
  'a 5th passenger is still refused -- the cap moved to 4, it was not removed'
);

select throws_ok(
  $$ select public.compute_fare(3000, 'pooling', 'standard', 0) $$,
  '22023',
  null,
  'a trip with no passengers is rejected rather than priced'
);

-- ---------------------------------------------------------------------------
-- Beyond the printed table
-- ---------------------------------------------------------------------------
-- The published matrix stops at 20 km. A longer trip must still get a
-- defensible number rather than an error or a silent cap at the last row.

select is(public.compute_fare(21000, 'special'), 212.00::numeric,
  'past the printed table, special full fare continues at +P8.00 per km');

select is(public.compute_fare(21000, 'special', 'discounted'), 169.40::numeric,
  'past the printed table, special discounted fare continues at +P6.40 per km '
  '(the statutory 20% off the increment)');

select is(public.compute_fare(21000, 'pooling'), 53.00::numeric,
  'past the printed table, pooling full fare continues at +P2.00 per km');

select is(public.compute_fare(21000, 'pooling', 'discounted'), 42.60::numeric,
  'past the printed table, pooling discounted fare continues at +P1.60 per km');

-- ---------------------------------------------------------------------------
-- Provenance recorded in the data
-- ---------------------------------------------------------------------------
-- An auditor should be able to ask the database which ordinance it is charging
-- under without reading the migration history.

select results_eq(
  $$
    select ride_type::text, min_passengers, max_passengers, is_per_passenger
      from public.fare_matrix
     where is_active
     order by ride_type::text
  $$,
  $$ values ('pooling', 1, 4, true), ('special', 1, 3, false) $$,
  'passenger limits and per-passenger billing are recorded per ride type'
);

select is(
  (select count(*)::integer
     from public.fare_matrix
    where is_active
      and ordinance_ref = 'City Ordinance No. 743, s. 2022'),
  2,
  'both active fare rows cite the ordinance they were transcribed from'
);

select * from finish();

rollback;
