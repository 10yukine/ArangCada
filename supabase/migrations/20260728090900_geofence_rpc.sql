-- TODA geofence containment.
--
-- Dispatch must respect TODA terminal jurisdictions,
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
-- creating a hairline dead zone where no one can book.
--
-- ---------------------------------------------------------------------------
-- Breaking the tie an inclusive boundary creates
-- ---------------------------------------------------------------------------
-- Inclusive boundaries mean a point on a shared edge is covered by BOTH
-- neighbouring polygons. Returning both and letting the caller choose would
-- push a jurisdiction decision into client code, which is exactly where it must
-- not live. So this RPC resolves the tie itself and returns a single zone.
--
-- The tiebreaker is proximity to the zone's own registered terminal:
-- ST_Distance between the input point and each candidate's terminal_point,
-- nearest wins. Rationale: the terminal is where that TODA's drivers actually
-- queue, so the nearest terminal is the best static proxy for shortest pickup
-- time. The alternatives are worse -- registration order or alphabetical code
-- would hand a boundary fare to whichever TODA happened to be inserted first,
-- which is arbitrary and indefensible to a TODA officer asking why their
-- terminal keeps losing edge pickups.
--
-- Distance is computed in the geography type, so the comparison is in metres on
-- the spheroid. Comparing raw 4326 geometry would compare DEGREES, and a degree
-- of longitude at Calamba's latitude is ~3% shorter than a degree of latitude --
-- enough to pick the wrong terminal when two sit at similar range but different
-- bearings.
--
-- Determinism matters: the same pickup must always resolve to the same TODA.
-- Distance ties fall back to `code`, which is unique, so the result is stable.
-- Zones with no registered terminal sort last (NULLS LAST) so they can never win
-- a contested edge, but they are still returned when they are the only match --
-- an unmapped terminal must not make a zone unbookable.
--
-- NOTE: this is jurisdiction routing, not driver assignment. The nearest
-- terminal is not necessarily where the nearest *available* driver is. The
-- dispatch RPC (ROADMAP M2W8) must still consider live driver availability;
-- this function only answers "whose jurisdiction is this pickup in".

-- ---------------------------------------------------------------------------
-- Which TODA zone serves this coordinate?
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
  with input as (
    select st_setsrid(st_makepoint(p_lon, p_lat), 4326) as g
  )
  select z.id, z.code, z.name
    from public.toda_zones z
   cross join input i
   where z.is_active
     and st_covers(z.boundary, i.g)
   order by
     st_distance(z.terminal_point::geography, i.g::geography) nulls last,
     z.code
   limit 1;
$$;

comment on function public.toda_zone_covering(double precision, double precision) is
  'The single active TODA zone serving the given lon/lat. Boundary-inclusive '
  '(ST_Covers), so a point exactly on an edge is serviceable. Where adjacent '
  'zones share that edge, the zone with the nearest registered terminal wins; '
  'ties fall back to code for determinism.';

-- ---------------------------------------------------------------------------
-- Does a specific zone cover this coordinate?
-- ---------------------------------------------------------------------------
-- Used when validating that a pickup falls inside the jurisdiction of the TODA
-- a driver actually belongs to.
--
-- Deliberately NOT tie-broken. "Which TODA serves this pickup" and "is this
-- pickup inside zone X" are different questions. A driver from the zone that
-- loses a boundary tiebreak is still legitimately standing in their own
-- jurisdiction, and validation must not tell them otherwise. Keeping this
-- inclusive avoids stranding drivers on shared edges.
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
  'included. Not tie-broken: a zone that loses a shared-edge tiebreak still '
  'contains the point. Returns false (never null) for unknown or inactive zones.';
