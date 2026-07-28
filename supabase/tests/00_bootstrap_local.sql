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
