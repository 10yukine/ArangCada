-- TODA terminal jurisdictions. `boundary` is the geofence consulted during
-- dispatch to decide which TODA may serve a pickup.

create table public.toda_zones (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  name           text not null,
  barangay       text,
  boundary       geometry(Polygon, 4326) not null,
  terminal_point geometry(Point, 4326),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  constraint toda_zones_boundary_valid check (st_isvalid(boundary))
);

comment on table public.toda_zones is
  'TODA terminal jurisdiction polygons for Calamba City. SRID 4326 (WGS84).';

create index toda_zones_boundary_gix on public.toda_zones using gist (boundary);
create index toda_zones_terminal_gix on public.toda_zones using gist (terminal_point);

alter table public.toda_zones enable row level security;

-- Zone boundaries are shared reference data: any signed-in user may read the
-- active ones. Only admins may change them.
create policy toda_zones_select_authenticated
  on public.toda_zones for select
  to authenticated
  using (is_active);

create policy toda_zones_admin_write
  on public.toda_zones for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
