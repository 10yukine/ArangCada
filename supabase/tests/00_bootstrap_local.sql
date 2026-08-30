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

-- raw_user_meta_data carries whatever the client passed to signUp()/
-- admin.createUser() as user metadata. handle_new_user() reads display_name
-- and mobile_number out of it to build the profiles row, so the shim needs
-- the column for that trigger to be testable at all.
create table if not exists auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text unique,
  raw_user_meta_data jsonb not null default '{}'::jsonb
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

-- Supabase also grants USAGE on schema auth to these roles by default, which
-- matters the moment any function body (not just an RLS policy expression --
-- those get their permission check baked in at definition time, which is why
-- this gap stayed invisible until a trigger called auth.uid() directly) calls
-- auth.uid() while running as one of them. Found while adding
-- guard_profiles_privileged_columns() in
-- 20260825120100_profiles_privileged_column_guard.sql.
grant usage on schema auth to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- pg_net stub (local only)
-- ---------------------------------------------------------------------------
-- pg_net ships with hosted Supabase and has no local build, so
-- 20260826032000_enable_pg_net.sql cannot run here. The FCM trigger on trips
-- calls net.http_post(), and without it EVERY insert into trips fails -- which
-- silently took out five assertions in 60_live_connected_vertical_slice_test
-- and made them look like real dispatch bugs.
--
-- This stub records nothing and performs no I/O. It exists so trips inserts
-- succeed locally; webhook delivery itself is only meaningfully testable
-- against the hosted project.

create schema if not exists net;

create or replace function net.http_post(
  url     text,
  body    jsonb default '{}'::jsonb,
  params  jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb,
  timeout_milliseconds integer default 5000
)
returns bigint
language sql
volatile
as $$
  select 0::bigint;
$$;

grant usage on schema net to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------
-- Supabase Vault stub (local only)
-- ---------------------------------------------------------------------------
-- 20260826031000_fcm_trigger_shared_secret.sql reads the webhook signing key
-- from vault.decrypted_secrets, which exists only on hosted Supabase. Without
-- it the trigger raises 'relation "vault.decrypted_secrets" does not exist',
-- every insert into trips aborts, and five assertions in
-- 60_live_connected_vertical_slice_test fail looking like dispatch bugs when
-- the dispatch logic is fine.
--
-- The value below is a fixed placeholder, deliberately not a secret: the local
-- webhook is a no-op stub, so nothing is signed and nothing is sent. Real
-- signing is only exercisable against the hosted project.

create schema if not exists vault;

create table if not exists vault.decrypted_secrets (
  id               uuid primary key default gen_random_uuid(),
  name             text unique,
  decrypted_secret text
);

insert into vault.decrypted_secrets (name, decrypted_secret)
values ('fcm_webhook_secret', 'local-stub-value-not-a-real-secret')
on conflict (name) do nothing;

grant usage on schema vault to anon, authenticated, service_role;
grant select on vault.decrypted_secrets to anon, authenticated, service_role;
