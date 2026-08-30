-- Supabase Security Advisor remediation (1 error + the genuinely actionable
-- warnings). Companion to 20260830120000, which handled the performance rules.

-- ---------------------------------------------------------------------------
-- 1. trips_fcm_webhook() is executable by PUBLIC and anon  (REAL exposure)
-- ---------------------------------------------------------------------------
-- This is a trigger function: it fires an outbound HTTP webhook for push
-- notifications. It is SECURITY DEFINER, so a direct call runs with the
-- definer's rights. Nothing outside the trigger should ever invoke it, and an
-- unauthenticated caller certainly should not -- that is a free webhook
-- generator pointed at our own endpoint.
--
-- Triggers do not consult EXECUTE privileges, so revoking here does not affect
-- the trigger firing on trips.

revoke execute on function public.trips_fcm_webhook() from public;
revoke execute on function public.trips_fcm_webhook() from anon;

-- ---------------------------------------------------------------------------
-- 2. rls_disabled_in_public on public.spatial_ref_sys  (the single ERROR)
-- ---------------------------------------------------------------------------
-- spatial_ref_sys is PostGIS's own SRID reference table, created in public
-- because PostGIS itself lives in public. It is the only RLS-disabled table in
-- the schema and therefore the sole Security Advisor error.
--
-- IMPORTANT: enabling RLS without a policy would break PostGIS. ST_Transform
-- and friends read this table, and under RLS a non-superuser with no policy
-- sees zero rows -- coordinate transforms would start failing at runtime
-- rather than loudly at deploy time. So RLS and a read policy go together, in
-- that order, in one statement block.
--
-- The contents are public reference data (EPSG definitions), not user data, so
-- an unrestricted read policy is the correct grant, not a workaround.
--
-- Wrapped in an exception guard: on hosted Supabase this table is owned by
-- supabase_admin, and the migration role may lack the ownership required to
-- ALTER it. If that is the case we log and continue rather than failing the
-- whole migration -- the advisor finding is cosmetic-risk, and a hard failure
-- here would block every later migration.

do $$
begin
  alter table public.spatial_ref_sys enable row level security;

  if not exists (
    select 1 from pg_policy p
     where p.polrelid = 'public.spatial_ref_sys'::regclass
       and p.polname = 'spatial_ref_sys_read_all'
  ) then
    create policy spatial_ref_sys_read_all
      on public.spatial_ref_sys
      for select
      using (true);
  end if;

  raise notice 'spatial_ref_sys: RLS enabled with an open read policy';
exception
  when insufficient_privilege then
    raise notice 'spatial_ref_sys: not owned by this role, left unchanged (advisor error will persist)';
  when others then
    raise notice 'spatial_ref_sys: skipped (%)', sqlerrm;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. duplicate_index on fare_discount_brackets
-- ---------------------------------------------------------------------------
--   fare_discount_brackets_unique_row  UNIQUE btree (fare_matrix_id, km)
--   fare_discount_brackets_lookup_idx         btree (fare_matrix_id, km)
--
-- Identical columns in identical order. A unique btree already serves every
-- lookup, range scan and sort the plain index could, so the second is dead
-- weight that must still be maintained on every write. Dropping the plain one
-- and keeping the unique one also keeps the constraint it enforces.

drop index if exists public.fare_discount_brackets_lookup_idx;

-- ---------------------------------------------------------------------------
-- Deliberately NOT changed, with reasons
-- ---------------------------------------------------------------------------
-- extension_in_public (postgis): relocating PostGIS to the extensions schema
--   would require every migration, function and index referencing public
--   geometry types to be revisited, and PostGIS upgrades on hosted Supabase
--   assume its installed schema. The exposure is a reference table and a set of
--   geometry functions, and item 2 above closes the only part with an actual
--   read surface. Not worth the blast radius for a capstone MVP.
--
-- "Signed-In Users Can Execute SECURITY DEFINER Function" (41 functions):
--   these are the app's own RPCs -- accept_ride, admin_review_driver and so on.
--   They are SECURITY DEFINER *by design*, because they must write rows the
--   caller cannot write directly, and they are meant to be called by signed-in
--   users. Revoking EXECUTE from authenticated would break dispatch, driver
--   review and onboarding outright. Their safety comes from the authorization
--   checks inside each body (is_admin / has_admin_scope / ownership tests),
--   which 40_rls_test.sql exercises. This warning class is expected here and
--   should be read as "audit these bodies", not "revoke these grants".
--
-- multiple_permissive_policies (driver_profiles SELECT): merging
--   driver_profiles_select_admin with driver_profiles_select_scoped_toda is
--   equivalent on paper, since Postgres ORs permissive policies. It is left
--   alone anyway: the gain is one fewer policy evaluation on a small table,
--   and the cost is editing live authorization without test coverage aimed
--   specifically at that pair. Wrong trade for the size of the win.
