-- Refactor: store fares as integer centavos rather than numeric pesos.
--
-- Money in a fare table is counted, not measured. Integers remove any question
-- of scale/rounding drift when fares are summed into a trip ledger later, and
-- they make the fare arithmetic exact.

alter table public.fare_matrix
  add column base_fare_centavos integer,
  add column per_km_centavos    integer;

update public.fare_matrix
set base_fare_centavos = round(base_fare_php * 100)::integer,
    per_km_centavos    = round(per_km_php * 100)::integer;

alter table public.fare_matrix
  alter column base_fare_centavos set not null,
  alter column per_km_centavos    set not null;

alter table public.fare_matrix
  drop constraint fare_matrix_base_fare_nonneg,
  drop constraint fare_matrix_per_km_nonneg;

alter table public.fare_matrix
  drop column base_fare_php,
  drop column per_km_php;

alter table public.fare_matrix
  add constraint fare_matrix_base_fare_nonneg check (base_fare_centavos >= 0),
  add constraint fare_matrix_per_km_nonneg    check (per_km_centavos >= 0);

comment on column public.fare_matrix.base_fare_centavos is
  'Base fare in centavos. 2500 = PHP 25.00.';
comment on column public.fare_matrix.per_km_centavos is
  'Charge per started kilometre beyond the base bracket, in centavos.';
