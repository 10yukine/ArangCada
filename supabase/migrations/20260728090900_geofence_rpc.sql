-- TODA geofence containment.
--
-- Dispatch must respect TODA terminal jurisdictions (CLAUDE.md objective 1),
-- and that check runs here in PostGIS -- never on the client, where it could be
-- bypassed by a modified app.
--
-- ---------------------------------------------------------------------------
-- Boundary semantics: ST_Covers, not ST_Contains
-- ---------------------------------------------------------------------------
-- These differ *only* for points lying exactly on the polygon edge:
--
--   ST_Contains(polygon, point_on_edge) -> false
--   ST_Covers  (polygon, point_on_edge) -> true
--
-- We use ST_Covers deliberately. A TODA boundary is a survey approximation
-- drawn down the middle of a road, and a commuter standing on that line is a
-- real, ordinary case. With ST_Contains, two adjacent TODAs whose polygons
-- share an edge would both reject a passenger standing on the shared line,
-- creating a hairline dead zone where no one can book. ST_Covers makes the
-- boundary inclusive so the edge is always serviceable.
--
-- The consequence is that a point on a shared edge matches BOTH neighbouring
-- zones. That is intentional and preferable to matching neither: picking
-- between candidates is a dispatch-priority decision, not a geometry one.
-- toda_zone_covering() therefore returns all matches in deterministic order
-- rather than silently choosing.

-- ---------------------------------------------------------------------------
-- Which active TODA zone(s) cover this coordinate?
-- ---------------------------------------------------------------------------
-- security definer so a boundary check does not depend on the caller's ability
-- to read toda_zones; search_path pinned so the definer right cannot be
-- redirected to an attacker-controlled schema.
create or replace function public.toda_zone_covering(
  p_lon double precision,
  p_lat double precision
)
returns table (
  zone_id  uuid,
  code     text,
  name     text
)
language sql
stable
security definer
set search_path = public
as $$
  select z.id, z.code, z.name
    from public.toda_zones z
   where z.is_active
     and st_covers(z.boundary, st_setsrid(st_makepoint(p_lon, p_lat), 4326))
   order by z.code;
$$;

comment on function public.toda_zone_covering(double precision, double precision) is
  'Active TODA zones whose boundary covers the given lon/lat. Boundary-inclusive '
  '(ST_Covers), so a point exactly on the edge is serviceable. May return more '
  'than one row where zones share an edge.';

-- ---------------------------------------------------------------------------
-- Does a specific zone cover this coordinate?
-- ---------------------------------------------------------------------------
-- Used when validating that a pickup falls inside the jurisdiction of the TODA
-- a driver actually belongs to.
create or replace function public.is_point_in_toda_zone(
  p_zone_id uuid,
  p_lon     double precision,
  p_lat     double precision
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.toda_zones z
     where z.id = p_zone_id
       and z.is_active
       and st_covers(z.boundary, st_setsrid(st_makepoint(p_lon, p_lat), 4326))
  );
$$;

comment on function public.is_point_in_toda_zone(uuid, double precision, double precision) is
  'True when the coordinate falls inside the given active TODA zone, boundary '
  'included. Returns false (never null) for unknown or inactive zones.';
