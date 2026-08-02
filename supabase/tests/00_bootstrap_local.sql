-- LOCAL TEST BOOTSTRAP — NOT A MIGRATION, NOT DEPLOYED.
--
-- Supabase supplies the `auth` schema and the anon/authenticated/service_role
-- roles in a real project. This file recreates the minimum surface those
-- migrations depend on so the schema and pgTAP suite can run against a plain
-- PostgreSQL + PostGIS instance (WSL Ubuntu, no Docker).
--
-- Keeping the shim here rather than in supabase/migrations/ means the migration
-- set stays exactly what gets applied to the real Supabase project.

create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text unique
);

-- Supabase reads the caller's user id from a request-scoped JWT claim.
-- Tests impersonate a user with:  set local request.jwt.claim.sub = '<uuid>';
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Table privileges.
--
-- Supabase pre-grants anon/authenticated/service_role on the public schema, and
-- leans on RLS as the only real gate. A plain PostgreSQL instance grants
-- nothing, and that difference silently invalidates RLS tests: without these
-- grants `set role authenticated; select from profiles` fails with "permission
-- denied" rather than returning zero rows. An assertion written against that
-- would pass identically with RLS switched off, proving nothing.
--
-- ALTER DEFAULT PRIVILEGES rather than GRANT ON ALL TABLES because this shim is
-- applied *before* the migrations, so there are no tables to grant on yet. The
-- migrations run as the same role in the same script, so the defaults apply to
-- every table they create.
-- ---------------------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
