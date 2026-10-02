-- API callers cannot change PostGIS's SRID table (release audit, 2 Oct 2026).
--
-- public.spatial_ref_sys belongs to the platform role that installed PostGIS.
-- On the hosted project that role granted anon and authenticated INSERT,
-- UPDATE, DELETE and TRUNCATE on it, and RLS is off, so the REST API accepted
-- writes to it from a signed-out caller. Distance and transform functions read
-- this table; removing or rewriting a row breaks dispatch and fares.
--
-- The migration role is not the owner: it cannot enable RLS (20260830130000
-- tried and logged the refusal) and cannot revoke another role's grants. It
-- does hold TRIGGER on the table, so the writes are refused by a trigger.
-- Roles other than anon and authenticated are untouched, which leaves the
-- platform free to maintain the table.

-- Takes effect where this role made the grants (local stacks). Elsewhere
-- Postgres answers with a warning and the trigger below does the work.
revoke insert, update, delete, truncate on public.spatial_ref_sys from anon, authenticated;

create or replace function public.spatial_ref_sys_api_read_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user in ('anon', 'authenticated') then
    raise exception 'spatial_ref_sys is read-only' using errcode = '42501';
  end if;
  return coalesce(new, old);
end;
$$;

revoke execute on function public.spatial_ref_sys_api_read_only() from public, anon, authenticated;

drop trigger if exists spatial_ref_sys_api_read_only on public.spatial_ref_sys;
create trigger spatial_ref_sys_api_read_only
  before insert or update or delete on public.spatial_ref_sys
  for each row execute function public.spatial_ref_sys_api_read_only();

drop trigger if exists spatial_ref_sys_api_no_truncate on public.spatial_ref_sys;
create trigger spatial_ref_sys_api_no_truncate
  before truncate on public.spatial_ref_sys
  for each statement execute function public.spatial_ref_sys_api_read_only();
