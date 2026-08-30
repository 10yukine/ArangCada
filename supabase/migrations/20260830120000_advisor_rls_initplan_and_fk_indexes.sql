-- Supabase Performance Advisor remediation.
--
-- Two findings, both behaviour-preserving.
--
-- ---------------------------------------------------------------------------
-- 1. auth_rls_initplan  (15 policies)
-- ---------------------------------------------------------------------------
-- A bare auth.uid() inside a policy is re-evaluated once PER ROW scanned.
-- Wrapping it as (select auth.uid()) turns it into an InitPlan that Postgres
-- evaluates once per query and reuses. Same result, materially less work as
-- soon as a table holds more than a handful of rows -- which trips and
-- trip_messages will.
--
-- These 15 are the original policies from the early schema migrations. The 13
-- policies added later already follow the wrapped convention and are left
-- alone; re-wrapping them would produce (select (select auth.uid())).
--
-- The statements below were generated from the live policy definitions via
-- pg_get_expr rather than retyped, so each USING / WITH CHECK expression is
-- exactly what was there before apart from the wrap. ALTER POLICY preserves
-- the policy name, command and role list.

alter policy admin_audit_logs_select_admin on public.admin_audit_logs using (is_admin((select auth.uid())));
alter policy driver_documents_admin_all on public.driver_documents using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy driver_documents_insert_own on public.driver_documents with check ((driver_id = (select auth.uid())));
alter policy driver_documents_select_own on public.driver_documents using ((driver_id = (select auth.uid())));
alter policy driver_profiles_select_admin on public.driver_profiles using (is_admin((select auth.uid())));
alter policy driver_profiles_select_own on public.driver_profiles using ((id = (select auth.uid())));
alter policy fare_discount_brackets_admin_write on public.fare_discount_brackets using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy fare_matrix_admin_write on public.fare_matrix using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy profiles_select_admin on public.profiles using (is_admin((select auth.uid())));
alter policy profiles_select_own on public.profiles using ((id = (select auth.uid())));
alter policy profiles_update_own on public.profiles using ((id = (select auth.uid()))) with check ((id = (select auth.uid())));
alter policy toda_members_select_admin on public.toda_members using (is_admin((select auth.uid())));
alter policy toda_zones_admin_write on public.toda_zones using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));
alter policy trips_insert_own on public.trips with check ((rider_id = (select auth.uid())));
alter policy trips_select_participant on public.trips using (((rider_id = (select auth.uid())) OR (driver_id = (select auth.uid()))));

-- ---------------------------------------------------------------------------
-- 2. unindexed_foreign_keys  (12 constraints)
-- ---------------------------------------------------------------------------
-- Postgres does not index a foreign key automatically. Without one, every
-- DELETE or UPDATE of the referenced parent row sequentially scans the child
-- table to enforce the constraint, and joins across the key cannot use an
-- index either.
--
-- Purely additive: no existing query changes behaviour, only its plan.
-- Written as plain CREATE INDEX rather than CONCURRENTLY because Supabase runs
-- each migration inside a transaction, which forbids CONCURRENTLY. These
-- tables are small at this stage so the brief write lock is not a concern; if
-- one of them is ever large in production, build that index CONCURRENTLY out
-- of band instead.

create index if not exists idx_app_evaluation_settings_updated_by on public.app_evaluation_settings (updated_by);
create index if not exists idx_driver_documents_reviewed_by on public.driver_documents (reviewed_by);
create index if not exists idx_driver_feedback_obligations_toda_zone_id on public.driver_feedback_obligations (toda_zone_id);
create index if not exists idx_driver_profiles_promoted_by on public.driver_profiles (promoted_by);
create index if not exists idx_driver_profiles_reviewed_by on public.driver_profiles (reviewed_by);
create index if not exists idx_driver_profiles_toda_member_id on public.driver_profiles (toda_member_id);
create index if not exists idx_reported_trip_chats_reporter_id on public.reported_trip_chats (reporter_id);
create index if not exists idx_sos_reports_reporter_id on public.sos_reports (reporter_id);
create index if not exists idx_sos_reports_trip_id on public.sos_reports (trip_id);
create index if not exists idx_trip_events_actor_id on public.trip_events (actor_id);
create index if not exists idx_trip_messages_sender_id on public.trip_messages (sender_id);
create index if not exists idx_trips_toda_zone_id on public.trips (toda_zone_id);

-- ---------------------------------------------------------------------------
-- Deliberately NOT addressed here
-- ---------------------------------------------------------------------------
-- extension_in_public (PostGIS): relocating an extension schema is disruptive
--   and 20260825150000_security_advisor_hardening.sql already records it as
--   needing a separate compatibility review. Unchanged.
-- multiple_permissive_policies (driver_profiles SELECT): merging
--   driver_profiles_select_admin and driver_profiles_select_scoped_toda would
--   change who can read what. That is an authorization decision, not a
--   performance tweak, so it is left for a deliberate review.
-- duplicate_index (fare_discount_brackets): the lookup index overlaps the
--   unique constraint. Dropping an index is not reversible from a migration
--   without knowing which query shapes depend on it. Left for review.
