-- TODA membership roster.
--
-- WHY THIS TABLE EXISTS
--
-- Driver onboarding is admin-initiated: an administrator resolves a person by
-- email or mobile number and grants them the driver role. The obvious question
-- a panelist asks is "what stops an administrator promoting someone who is not
-- actually a TODA member?" This table is the answer -- the admin review screen
-- can show whether the applicant matches a roster entry.
--
-- ADVISORY, NOT A HARD GATE
--
-- A roster match is displayed, never required. A roster that is stale or
-- incomplete would otherwise make onboarding impossible for a legitimate new
-- member, which is a worse failure than showing an administrator "no roster
-- match" and letting them exercise judgement.
--
-- WHY NO DRIVER CAN READ IT, NOT EVEN THEIR OWN ROW
--
-- Every row pairs a real person's name with a body number and plate. That is a
-- directory of who drives which tricycle -- exactly the sort of aggregate a
-- commuter should never be able to pull, and there is no feature that needs a
-- driver to read their own roster entry. Admin select only.

create table public.toda_members (
  id                uuid primary key default gen_random_uuid(),
  toda_zone_id      uuid not null references public.toda_zones (id) on delete cascade,
  member_name       text not null,
  body_number       text not null,
  plate_number      text,
  mtop_franchise_no text,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  -- A body number identifies a unit within its own TODA, not city-wide, so
  -- uniqueness is scoped to the zone.
  constraint toda_members_zone_body_key unique (toda_zone_id, body_number)
);

comment on table public.toda_members is
  'TODA membership roster, consulted advisorily during driver onboarding. '
  'Contains real names and plate numbers: admin-readable only.';

create index toda_members_zone_idx on public.toda_members (toda_zone_id);

alter table public.toda_members enable row level security;

create policy toda_members_select_admin
  on public.toda_members for select
  using (public.is_admin(auth.uid()));

-- Deliberately no insert/update/delete policy. The roster is reference data
-- maintained through migrations and seed files, the same way toda_zones and
-- fare_matrix are, so it is auditable in version control rather than editable
-- from a session.
