-- ArangCada demo seed data (development and internal testing only).
--
-- ⚠ PLACEHOLDER VALUES — NOT OFFICIAL LGU DATA.
-- Both the TODA boundary polygons and the fare brackets below are invented
-- stand-ins so the dispatch and fare logic can be exercised end to end. They
-- MUST be replaced with the digitized Calamba TODA boundaries and the actual
-- LGU-approved fare ordinance figures before any evaluation or panel demo.
-- Tracked in ROADMAP.md, Month 1 Week 3.

-- ---------------------------------------------------------------------------
-- TODA zones
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
-- Fare matrix
-- ---------------------------------------------------------------------------
-- Base fare covers the first base_distance_m metres; every *started* kilometre
-- beyond that adds per_km_php. Pooling is cheaper per the capstone scope.

insert into public.fare_matrix (ride_type, base_fare_php, base_distance_m, per_km_php)
values
  ('special', 25.00, 1000, 8.00),
  ('pooling', 15.00, 1000, 5.00);
