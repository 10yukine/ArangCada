-- Trip (booking) records and their status machine.
--
-- Status transitions follow the machine documented in CLAUDE.md. Final fare is
-- written by trusted server-side logic, never by the client.

create type public.trip_status as enum (
  'requested',
  'searching_driver',
  'driver_assigned',
  'accepted',
  'driver_en_route',
  'arrived',
  'in_progress',
  'completed',
  'cancelled_by_rider',
  'cancelled_by_driver',
  'no_driver_available',
  'emergency_reported'
);

create table public.trips (
  id              uuid primary key default gen_random_uuid(),
  rider_id        uuid not null references public.profiles (id),
  driver_id       uuid references public.profiles (id),
  toda_zone_id    uuid references public.toda_zones (id),
  ride_type       public.ride_type not null default 'special',
  status          public.trip_status not null default 'requested',
  pickup          geometry(Point, 4326) not null,
  dropoff         geometry(Point, 4326) not null,
  distance_m      integer,
  fare_estimate   numeric(8, 2),
  final_fare      numeric(8, 2),
  idempotency_key text unique,
  requested_at    timestamptz not null default now(),
  completed_at    timestamptz,
  updated_at      timestamptz not null default now(),
  constraint trips_distance_nonneg
    check (distance_m is null or distance_m >= 0),
  constraint trips_driver_required_after_assignment
    check (
      status in ('requested', 'searching_driver', 'cancelled_by_rider', 'no_driver_available')
      or driver_id is not null
    )
);

comment on table public.trips is
  'Booking records. idempotency_key guards against duplicate submits on weak mobile data.';

create index trips_rider_idx on public.trips (rider_id);
create index trips_driver_idx on public.trips (driver_id);
create index trips_status_idx on public.trips (status);
create index trips_pickup_gix on public.trips using gist (pickup);

-- "A commuter cannot have more than one active ride" (CLAUDE.md), enforced in
-- the database so a racing double-submit cannot create two live trips.
create unique index trips_one_active_per_rider
  on public.trips (rider_id)
  where status in (
    'requested', 'searching_driver', 'driver_assigned', 'accepted',
    'driver_en_route', 'arrived', 'in_progress', 'emergency_reported'
  );

alter table public.trips enable row level security;

-- Only the rider and the assigned driver may see a trip. Location and trip
-- detail must not leak to other users.
create policy trips_select_participant
  on public.trips for select
  using (rider_id = auth.uid() or driver_id = auth.uid());

create policy trips_insert_own
  on public.trips for insert
  with check (rider_id = auth.uid());

create policy trips_admin_all
  on public.trips for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
