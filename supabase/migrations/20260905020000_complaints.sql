-- Complaints: bidirectional, trip-linked, non-emergency issue reports.
--
-- WHY THIS EXISTS
--
-- `complaints` is one of the planned core tables but nothing ever read or
-- wrote it -- neither app, no migration. A commuter or driver had no way to
-- report an ordinary issue ("driver was late", "rider was rude", "wrong
-- route", "vehicle condition"). SOS (`sos_reports`, 20260825133421) exists
-- but is explicitly for danger/threat; routing an ordinary gripe through it
-- would train users to press the one button that must stay trustworthy for
-- real emergencies.
--
-- Bidirectional per owner decision 5 Sep 2026: a driver may also file one
-- about a commuter, mirroring sos_reports' existing reporter_role shape.
--
-- This migration is deliberately modelled line-for-line on
-- create_sos_report()/sos_reports/update_sos_status() -- same validation
-- shape, same RLS shape, same admin-audit shape. Diverges only where the
-- feature itself differs (below).

create table public.complaints (
  id                uuid primary key default gen_random_uuid(),
  trip_id           uuid not null references public.trips (id),
  toda_zone_id      uuid not null references public.toda_zones (id),
  complainant_id    uuid not null references public.profiles (id),
  complainant_role  text not null check (complainant_role in ('commuter', 'driver')),
  complainant_display_name text not null,
  respondent_id     uuid not null references public.profiles (id),
  respondent_display_name text not null,
  toda_name         text not null,
  category          text not null,
  description       text not null,
  status            text not null default 'new'
    check (status in ('new', 'acknowledged', 'investigating', 'resolved', 'dismissed')),
  admin_note        text,
  idempotency_key   text not null unique,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint complaints_description_length
    check (char_length(trim(description)) between 1 and 500),
  constraint complaints_note_length
    check (admin_note is null or char_length(admin_note) <= 1000),
  constraint complaints_category_known check (
    category in (
      -- commuter about driver
      'driver_late', 'unsafe_driving_non_emergency', 'rude_unprofessional',
      'wrong_route', 'vehicle_condition', 'overcharged',
      -- driver about commuter
      'passenger_late', 'damaged_vehicle_non_emergency', 'disputed_fare',
      -- shared
      'other'
    )
  )
);

create index complaints_zone_created_idx on public.complaints (toda_zone_id, created_at desc);
create index complaints_status_created_idx on public.complaints (status, created_at desc);
create index complaints_complainant_idx on public.complaints (complainant_id);
create index complaints_trip_idx on public.complaints (trip_id);

comment on table public.complaints is
  'Non-emergency issue reports, either direction (commuter about driver, or '
  'driver about commuter). Not for danger/threat -- see sos_reports for that. '
  'The respondent (person complained about) has no read access; only the '
  'complainant and a scoped admin do -- see the RLS policy below.';

alter table public.complaints enable row level security;

create policy complaints_select_complainant_or_scoped_admin
  on public.complaints for select
  to authenticated
  using (
    complainant_id = (select auth.uid())
    or public.has_admin_scope((select auth.uid()), toda_zone_id)
  );

-- No insert/update policy: create_complaint() and update_complaint_status()
-- below are the only writers, both security definer.

create or replace function public.create_complaint(
  p_trip_id uuid,
  p_category text,
  p_description text,
  p_idempotency_key text
)
returns public.complaints
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_complaint public.complaints%rowtype;
  v_complainant public.profiles%rowtype;
  v_role text;
  v_respondent uuid;
  v_respondent_name text;
begin
  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'a complaint idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_complaint from public.complaints
   where idempotency_key = p_idempotency_key;

  if found then
    if v_complaint.complainant_id <> auth.uid() or v_complaint.trip_id <> p_trip_id then
      raise exception 'that complaint key belongs to another report'
        using errcode = '42501';
    end if;
    return v_complaint;
  end if;

  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
    raise exception 'only a trip participant can file a complaint about it'
      using errcode = '42501';
  end if;

  -- Unlike SOS, a complaint is commonly filed AFTER the trip ends ("driver
  -- was late" only makes sense in hindsight), so every status is allowed
  -- except the ones where no ride actually happened.
  if v_trip.status in ('requested', 'searching_driver', 'cancelled_by_rider',
                        'cancelled_by_driver', 'no_driver_available') then
    raise exception 'a complaint requires a trip that actually had a driver assigned'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_description, '')), '') is null
     or char_length(trim(p_description)) > 500 then
    raise exception 'a complaint description is required'
      using errcode = '22023';
  end if;

  select * into v_complainant from public.profiles where id = auth.uid();

  if auth.uid() = v_trip.driver_id then
    v_role := 'driver';
    v_respondent := v_trip.rider_id;
    v_respondent_name := v_trip.rider_display_name;
  else
    v_role := 'commuter';
    v_respondent := v_trip.driver_id;
    v_respondent_name := v_trip.driver_display_name;
  end if;

  if v_respondent is null then
    raise exception 'this trip has no other participant to complain about'
      using errcode = '22023';
  end if;

  insert into public.complaints (
    trip_id, toda_zone_id, complainant_id, complainant_role,
    complainant_display_name, respondent_id, respondent_display_name,
    toda_name, category, description, idempotency_key
  )
  values (
    p_trip_id,
    v_trip.toda_zone_id,
    v_complainant.id,
    v_role,
    v_complainant.display_name,
    v_respondent,
    v_respondent_name,
    v_trip.toda_name,
    trim(p_category),
    trim(p_description),
    p_idempotency_key
  )
  returning * into v_complaint;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'complaint.filed');

  return v_complaint;
end;
$$;

comment on function public.create_complaint(uuid, text, text, text) is
  'Files a non-emergency complaint about the other participant on a trip. '
  'Role and respondent are derived server-side from which id matches '
  'auth.uid(), never client-supplied. Idempotent on p_idempotency_key.';

revoke execute on function public.create_complaint(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.create_complaint(uuid, text, text, text)
  to authenticated, service_role;

create or replace function public.update_complaint_status(
  p_complaint_id uuid,
  p_status text,
  p_note text
)
returns public.complaints
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_complaint public.complaints%rowtype;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can update a complaint'
      using errcode = '42501';
  end if;

  if p_status not in ('acknowledged', 'investigating', 'resolved', 'dismissed') then
    raise exception 'unknown complaint status'
      using errcode = '22023';
  end if;

  select * into v_complaint from public.complaints where id = p_complaint_id for update;
  if not found then
    raise exception 'the complaint does not exist'
      using errcode = 'P0002';
  end if;
  if v_complaint.status in ('resolved', 'dismissed') and v_complaint.status <> p_status then
    raise exception 'a closed complaint cannot be reopened through this action'
      using errcode = '22023';
  end if;

  update public.complaints
     set status = p_status,
         admin_note = nullif(trim(coalesce(p_note, '')), ''),
         updated_at = now()
   where id = p_complaint_id
   returning * into v_complaint;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    auth.uid(),
    'complaint.' || p_status,
    v_complaint.respondent_id,
    jsonb_build_object('complaint_id', v_complaint.id, 'trip_id', v_complaint.trip_id)
  );

  return v_complaint;
end;
$$;

comment on function public.update_complaint_status(uuid, text, text) is
  'Admin-only status transition on a complaint. Writes one admin_audit_logs '
  'row per change. Mirrors update_sos_status() exactly.';

revoke execute on function public.update_complaint_status(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.update_complaint_status(uuid, text, text)
  to authenticated, service_role;
