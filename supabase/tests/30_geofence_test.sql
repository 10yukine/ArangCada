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

begin;

select plan(13);

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
