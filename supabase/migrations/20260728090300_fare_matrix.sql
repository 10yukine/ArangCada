-- LGU-approved distance fare parameters, one active row per ride type.
--
-- Fares are stored in pesos here; a later migration converts the money columns
-- to integer centavos once compute_fare() reads its rates from this table.

create type public.ride_type as enum ('special', 'pooling');

create table public.fare_matrix (
  id              uuid primary key default gen_random_uuid(),
  ride_type       public.ride_type not null,
  base_fare_php   numeric(8, 2) not null,
  base_distance_m integer not null,
  per_km_php      numeric(8, 2) not null,
  effective_from  date not null default current_date,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  constraint fare_matrix_base_distance_positive check (base_distance_m > 0),
  constraint fare_matrix_base_fare_nonneg check (base_fare_php >= 0),
  constraint fare_matrix_per_km_nonneg check (per_km_php >= 0)
);

comment on table public.fare_matrix is
  'LGU fare brackets. base_fare covers the first base_distance_m metres; each '
  'started kilometre beyond that adds per_km. No surge pricing.';

-- Exactly one active bracket per ride type, enforced by the database rather
-- than by application code.
create unique index fare_matrix_one_active_per_ride_type
  on public.fare_matrix (ride_type)
  where is_active;

alter table public.fare_matrix enable row level security;

create policy fare_matrix_select_authenticated
  on public.fare_matrix for select
  to authenticated
  using (is_active);

create policy fare_matrix_admin_write
  on public.fare_matrix for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
