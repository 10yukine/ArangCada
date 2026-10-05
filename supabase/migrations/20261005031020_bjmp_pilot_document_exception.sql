-- Temporary, owner-authorized document-free testing for BJMP TODA only.
-- Enrollment is still performed by an administrator; no account can opt in
-- through user metadata or the Data API. Never fabricate document approvals.
-- Revert before implementation with:
--   update public.bjmp_pilot_settings set enabled = false where id;
create table public.bjmp_pilot_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false
);
alter table public.bjmp_pilot_settings enable row level security;
revoke all on public.bjmp_pilot_settings from public, anon, authenticated;
insert into public.bjmp_pilot_settings (enabled) values (true);
comment on table public.bjmp_pilot_settings is
  'Temporary BJMP TODA document/approval exemption for testing; SQL-owner controlled. Disable before implementation. Does not verify documents or phone ownership.';

create or replace function public.can_driver_go_online(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.driver_profiles d
    join public.profiles p on p.id = d.id
    join auth.users u on u.id = p.id
    where d.id = p_uid and p.role = 'driver' and p.status = 'active'
      and (d.license_expires_on is null or d.license_expires_on >= current_date)
      and (p.phone_verified_at is not null or p.is_internal_tester)
      and (
        (p.is_internal_tester and
         u.raw_app_meta_data ->> 'driver_approval_test_bypass' = 'true')
        or exists (
          select 1 from public.bjmp_pilot_settings s
          join public.toda_zones z on z.id = d.toda_zone_id
          where s.id and s.enabled and z.code = 'CAL-TUR-BJMP'
            and z.is_active and not z.is_internal_test
        )
        or (
          d.verification_status = 'approved'
          and not exists (
            select 1 from unnest(public.driver_required_document_types()) required(document_type)
            where not exists (
              select 1 from public.driver_documents doc
              where doc.driver_id = d.id and doc.document_type = required.document_type
                and doc.status = 'approved'
            )
          )
        )
      )
  );
$$;

-- Disabling the exception immediately withdraws availability for drivers
-- who cannot meet the ordinary rules. Dispatch/acceptance also recheck the
-- same eligibility function, so stale clients cannot keep using the exception.
create function public.enforce_bjmp_pilot_availability()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.driver_availability a
  set is_online = false, updated_at = now()
  where a.is_online and not public.can_driver_go_online(a.driver_id)
    and exists (select 1 from public.driver_profiles d
                join public.toda_zones z on z.id = d.toda_zone_id
                where d.id = a.driver_id and z.code = 'CAL-TUR-BJMP');
  return null;
end;
$$;
revoke all on function public.enforce_bjmp_pilot_availability() from public, anon, authenticated;
create trigger bjmp_pilot_availability
  after update or delete on public.bjmp_pilot_settings
  for each statement execute function public.enforce_bjmp_pilot_availability();
