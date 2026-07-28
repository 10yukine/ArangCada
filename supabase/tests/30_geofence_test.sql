-- pgTAP: TODA geofence containment, with the on-border case as the centrepiece.
--
-- The seeded Poblacion zone is an axis-aligned rectangle with exact vertices:
--
--     (121.150, 14.230) +-------------------+ (121.180, 14.230)
--                       |                   |
--                       |    * interior     |
--                       |  (121.165,14.215) |
--                       |                   |
--     (121.150, 14.200) +-------------------+ (121.180, 14.200)
--
-- so (121.150, 14.215) sits exactly ON the western edge, and (121.150, 14.200)
-- sits exactly ON a vertex. Those are the points that separate ST_Covers from
-- ST_Contains, and they are the reason this file exists.
--
-- The seeded zones are far apart, so none of them can produce the case where an
-- inclusive boundary matches TWO zones at once. That case gets a dedicated
-- fixture below, built inside this transaction rather than added to seed.sql --
-- adjacency invented purely to exercise a tiebreaker does not belong in data
-- that is meant to stand in for real Calamba geography.

begin;

select plan(20);

-- ---------------------------------------------------------------------------
-- Existence
-- ---------------------------------------------------------------------------
select has_function(
  'public', 'toda_zone_covering',
  'toda_zone_covering() should exist'
);

select has_function(
  'public', 'is_point_in_toda_zone',
  'is_point_in_toda_zone() should exist'
);

-- ---------------------------------------------------------------------------
-- Unambiguous interior and exterior
-- ---------------------------------------------------------------------------
select is(
  (select code from public.toda_zone_covering(121.165, 14.215)),
  'CAL-POB-01',
  'a point well inside Poblacion resolves to that TODA'
);

select is(
  (select count(*) from public.toda_zone_covering(121.100, 14.215)),
  0::bigint,
  'a point outside every zone resolves to no TODA at all'
);

select is(
  (select code from public.toda_zone_covering(121.065, 14.185)),
  'CAL-CAN-01',
  'a Canlubang point resolves to Canlubang, not to the nearest other zone'
);

-- ---------------------------------------------------------------------------
-- ON THE BORDER -- the edge case this RPC is designed around
-- ---------------------------------------------------------------------------
select is(
  (select code from public.toda_zone_covering(121.150, 14.215)),
  'CAL-POB-01',
  'a pickup exactly ON the boundary line is inside the zone, not refused'
);

select is(
  (select count(*) from public.toda_zone_covering(121.150, 14.215)),
  1::bigint,
  'that on-border pickup resolves to exactly one zone'
);

select is(
  (select code from public.toda_zone_covering(121.150, 14.200)),
  'CAL-POB-01',
  'a pickup exactly on a boundary vertex is inside the zone'
);

-- These two assertions document *why* the RPC uses ST_Covers. If someone later
-- "simplifies" it to ST_Contains, the on-border tests above break and this pair
-- explains the reason.
select ok(
  not st_contains(
    (select boundary from public.toda_zones where code = 'CAL-POB-01'),
    st_setsrid(st_makepoint(121.150, 14.215), 4326)
  ),
  'ST_Contains EXCLUDES the on-border point -- using it would strand commuters '
  'standing on a TODA boundary'
);

select ok(
  st_covers(
    (select boundary from public.toda_zones where code = 'CAL-POB-01'),
    st_setsrid(st_makepoint(121.150, 14.215), 4326)
  ),
  'ST_Covers INCLUDES the on-border point -- hence the choice'
);

-- ---------------------------------------------------------------------------
-- SHARED EDGE between two adjacent zones -- the tie an inclusive boundary makes
-- ---------------------------------------------------------------------------
-- Two rectangles meeting exactly on the meridian lon = 121.320:
--
--   (121.300,14.320) +--------+--------+ (121.340,14.320)
--                    |  AAA   |  ZZZ   |
--                    |    x   |x       |     x = terminal
--                    |        |        |     * = pickup, on the shared edge
--   (121.300,14.300) +--------*--------+ (121.340,14.300)
--                         lon = 121.320
--
-- Codes are chosen adversarially: TEST-AAA sorts first alphabetically AND is
-- inserted first, but its terminal is ~1.6 km from the pickup while TEST-ZZZ's
-- is ~0.5 km. If the RPC returns TEST-ZZZ, distance beat both insertion order
-- and alphabetical order -- which is the whole claim being tested.

insert into public.toda_zones (code, name, barangay, boundary, terminal_point)
values
  (
    'TEST-AAA', 'West Fixture TODA', 'Fixture',
    st_geomfromtext(
      'POLYGON((121.300 14.300, 121.320 14.300, 121.320 14.320, 121.300 14.320, 121.300 14.300))',
      4326
    ),
    st_setsrid(st_makepoint(121.305, 14.310), 4326)
  ),
  (
    'TEST-ZZZ', 'East Fixture TODA', 'Fixture',
    st_geomfromtext(
      'POLYGON((121.320 14.300, 121.340 14.300, 121.340 14.320, 121.320 14.320, 121.320 14.300))',
      4326
    ),
    st_setsrid(st_makepoint(121.325, 14.310), 4326)
  );

-- Fixture sanity. Without this, the tiebreak assertions below could pass simply
-- because only one zone ever matched, leaving the tiebreaker untested.
select is(
  (select count(*)
     from public.toda_zones z
    where z.is_active
      and st_covers(z.boundary, st_setsrid(st_makepoint(121.320, 14.310), 4326))),
  2::bigint,
  'fixture sanity: the shared-edge point really is covered by BOTH adjacent zones'
);

select is(
  (select count(*) from public.toda_zone_covering(121.320, 14.310)),
  1::bigint,
  'a pickup on a shared edge resolves to exactly one zone, not two'
);

select is(
  (select code from public.toda_zone_covering(121.320, 14.310)),
  'TEST-ZZZ',
  'the winner is the zone with the nearer terminal, even though the loser sorts '
  'first alphabetically and was inserted first'
);

-- Causation, not coincidence: move the far terminal nearer and the winner must
-- flip. Without this, the assertion above would also pass if the RPC were
-- quietly ordering by something else that happened to favour TEST-ZZZ.
update public.toda_zones
   set terminal_point = st_setsrid(st_makepoint(121.3195, 14.310), 4326)
 where code = 'TEST-AAA';

select is(
  (select code from public.toda_zone_covering(121.320, 14.310)),
  'TEST-AAA',
  'moving a terminal closer flips the winner, confirming distance is what decides'
);

-- terminal_point is nullable, so a zone may have no registered terminal.
update public.toda_zones
   set terminal_point = null
 where code = 'TEST-AAA';

select is(
  (select code from public.toda_zone_covering(121.320, 14.310)),
  'TEST-ZZZ',
  'a zone with no registered terminal cannot win a contested edge'
);

select is(
  (select code from public.toda_zone_covering(121.310, 14.310)),
  'TEST-AAA',
  'but a zone with no terminal is still returned when it is the only match -- an '
  'unmapped terminal must not make a zone unbookable'
);

-- ---------------------------------------------------------------------------
-- Per-zone boolean helper
-- ---------------------------------------------------------------------------
select ok(
  public.is_point_in_toda_zone(
    (select id from public.toda_zones where code = 'CAL-POB-01'),
    121.150, 14.215
  ),
  'the per-zone helper agrees that on-border counts as inside'
);

select ok(
  not public.is_point_in_toda_zone(
    (select id from public.toda_zones where code = 'CAL-POB-01'),
    121.100, 14.215
  ),
  'the per-zone helper rejects a point outside that zone'
);

-- ---------------------------------------------------------------------------
-- Defensive cases
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.toda_zone_covering(null, 14.215)),
  0::bigint,
  'a null coordinate matches no zone rather than raising'
);

-- Deactivating a zone must remove it from dispatch. Kept last: it mutates the
-- seed data (rolled back with the surrounding transaction).
update public.toda_zones set is_active = false where code = 'CAL-POB-01';

select is(
  (select count(*) from public.toda_zone_covering(121.165, 14.215)),
  0::bigint,
  'a deactivated TODA zone stops serving dispatch lookups'
);

select * from finish();

rollback;
