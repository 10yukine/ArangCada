-- ArangCada demo seed data (development and internal testing only).
--
-- ⚠ THE TODA BOUNDARY POLYGONS BELOW ARE PLACEHOLDERS — NOT OFFICIAL LGU DATA.
-- They are invented stand-ins so the dispatch logic can be exercised end to end,
-- and they MUST be replaced with the digitized Calamba TODA boundaries before any
-- evaluation or panel demo. Tracked in ROADMAP.md, Month 1 Week 3.
--
-- The FARE data below is no longer a placeholder: it is transcribed from the
-- posted BPTFO "Minimum Fare Matrix" (Calamba City Ordinance No. 743, Series of
-- 2022).

-- ---------------------------------------------------------------------------
-- TODA zones  (⚠ placeholder geometry)
-- ---------------------------------------------------------------------------
-- Deliberately simple axis-aligned rectangles: exact, known vertices make
-- boundary behaviour testable (see supabase/tests for the on-border case).

insert into public.toda_zones (code, name, barangay, boundary, terminal_point)
values
  (
    'CAL-POB-01',
    'Calamba Poblacion TODA',
    'Poblacion',
    st_geomfromtext(
      'POLYGON((121.150 14.200, 121.180 14.200, 121.180 14.230, 121.150 14.230, 121.150 14.200))',
      4326
    ),
    st_setsrid(st_makepoint(121.1653, 14.2117), 4326)
  ),
  (
    'CAL-CAN-01',
    'Canlubang TODA',
    'Canlubang',
    st_geomfromtext(
      'POLYGON((121.050 14.170, 121.080 14.170, 121.080 14.200, 121.050 14.200, 121.050 14.170))',
      4326
    ),
    st_setsrid(st_makepoint(121.0650, 14.1850), 4326)
  );

-- ---------------------------------------------------------------------------
-- Fare matrix — Calamba City Ordinance No. 743, s. 2022
-- ---------------------------------------------------------------------------
-- Base fare covers the first 2 000 metres; every *started* kilometre beyond that
-- adds one full per-km increment. Amounts are centavos: 6000 = PHP 60.00.
--
-- Ride type mapping:
--   'pooling' = "Regular na Byahe"  — PHP 15.00 + PHP 2.00/km, PER PASSENGER, max 4
--   'special' = "Espesyal na Byahe" — PHP 60.00 + PHP 8.00/km, PER TRIP, 1-3 passengers
--
-- min_passengers/max_passengers below are the ORDINANCE TRANSCRIPTION and are
-- pinned by 15_lgu_ordinance_743_test.sql. They are not what the app enforces.
-- Since 31 Aug 2026 the LGU permits 4 passengers on Espesyal and pooling is no
-- longer bookable; both facts live in fare_matrix.operating_max_passengers and
-- fare_matrix.is_bookable, set by 20260831110000_special_only_four_passengers.sql.
-- Do not "fix" the 3 below to a 4 — it would make the database disagree with the
-- posted matrix.
--
-- discount_per_km_centavos is the statutory 20% applied to the per-km increment.
-- It is used only past the 20 km end of the printed table; inside it, the
-- transcribed fare_discount_brackets rows govern.

insert into public.fare_matrix (
  ride_type, base_fare_centavos, base_distance_m, per_km_centavos,
  discount_per_km_centavos, min_passengers, max_passengers,
  is_per_passenger, ordinance_ref, printed_max_km,
  operating_max_passengers, is_bookable
)
values
  -- min/max_passengers are the ordinance transcription (Espesyal 1-3).
  -- operating_max_passengers and is_bookable are the LGU operating decisions of
  -- 31 Aug 2026: Espesyal carries 4 and is the only bookable type.
  ('special', 6000, 2000, 800, 640, 1, 3, false, 'City Ordinance No. 743, s. 2022', 20, 4,    true),
  ('pooling', 1500, 2000, 200, 160, 1, 4, true,  'City Ordinance No. 743, s. 2022', 20, null, false);

-- ---------------------------------------------------------------------------
-- Senior Citizen / PWD / student column — transcribed verbatim
-- ---------------------------------------------------------------------------
-- These are the printed amounts, not a computed 20%. Two regular-fare rows do
-- not follow any consistent rounding rule (4 km prints P15.50 where 20% yields
-- P15.20; 16 km prints P34.00 where 20% yields P34.40). The tarpaulin is what
-- the LGU enforces, so the tarpaulin is what the database stores.
--
-- km = the printed row. Row 2 is the "First 2km" row.

insert into public.fare_discount_brackets (fare_matrix_id, km, fare_centavos)
select fm.id, v.km, v.fare_centavos
  from public.fare_matrix fm
  join (values
          -- Regular na Byahe — Senior Citizen, P.W.D., at Estudyante
          ( 2,  1200), ( 3,  1350), ( 4,  1550), ( 5,  1700), ( 6,  1850),
          ( 7,  2000), ( 8,  2200), ( 9,  2300), (10,  2500), (11,  2650),
          (12,  2800), (13,  3000), (14,  3150), (15,  3300), (16,  3400),
          (17,  3600), (18,  3750), (19,  3900), (20,  4100)
       ) as v (km, fare_centavos) on true
 where fm.ride_type = 'pooling'
   and fm.is_active;

insert into public.fare_discount_brackets (fare_matrix_id, km, fare_centavos)
select fm.id, v.km, v.fare_centavos
  from public.fare_matrix fm
  join (values
          -- Espesyal na Byahe — Senior Citizen, P.W.D., at Estudyante
          ( 2,  4800), ( 3,  5400), ( 4,  6100), ( 5,  6700), ( 6,  7400),
          ( 7,  8000), ( 8,  8600), ( 9,  9300), (10,  9900), (11, 10600),
          (12, 11200), (13, 11800), (14, 12500), (15, 13100), (16, 13800),
          (17, 14400), (18, 15000), (19, 15700), (20, 16300)
       ) as v (km, fare_centavos) on true
 where fm.ride_type = 'special'
   and fm.is_active;
