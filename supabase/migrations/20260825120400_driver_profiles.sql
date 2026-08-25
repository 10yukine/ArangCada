-- Driver record and verification state.
--
-- WHY A SEPARATE TABLE RATHER THAN COLUMNS ON profiles
--
-- Row existence *is* the "is this person a driver" check, commuters carry no
-- permanently-null driver columns, and profiles' policy set -- which already
-- needs the is_admin() security-definer workaround to avoid infinite RLS
-- recursion -- stays untouched. This table was already planned in CLAUDE.md's
-- Suggested Core Tables; it is not a new invention.
--
-- WHY 'suspended' IS NOT IN THIS ENUM
--
-- Suspension is an account-level state and already exists as
-- profiles.status = 'suspended'. Duplicating it here would create two sources
-- of truth for one fact and an inevitable disagreement between them. A UI that
-- needs to show Approved / Rejected / Suspended composes it from both columns.
--
-- WHY THERE IS NO license_number COLUMN
--
-- The licence document itself goes to private Storage, and it carries the
-- number. A separate column would duplicate PII into something queryable for
-- no functional gain (CLAUDE.md rule 10). license_expires_on is stored instead:
-- a date is not an identifier, and it lets can_driver_go_online() refuse a
-- lapsed licence continuously rather than relying on an administrator to
-- notice. See .pipeline/specs.md §3.

create type public.driver_verification_status as enum (
  'unverified',
  'pending_review',
  'approved',
  'rejected'
);

create table public.driver_profiles (
  id                  uuid primary key references public.profiles (id) on delete cascade,
  toda_zone_id        uuid not null references public.toda_zones (id),
  -- Advisory link to the roster, set when the onboarding lookup found a match.
  -- Nullable: a legitimate new member may not be on the roster copy we hold.
  toda_member_id      uuid references public.toda_members (id),
  -- Nullable because the order in which a TODA assigns a body number is not
  -- yet confirmed (docs/CLIENT_MEETING_QUESTIONS.md A4). A driver can be
  -- onboarded before one exists and have it filled in later.
  body_number         text,
  plate_number        text,
  license_expires_on  date,
  verification_status public.driver_verification_status not null default 'unverified',
  submitted_at        timestamptz,
  reviewed_by         uuid references public.profiles (id),
  reviewed_at         timestamptz,
  rejection_reason    text,
  promoted_by         uuid not null references public.profiles (id),
  promoted_at         timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint driver_profiles_rejection_reason_required
    check (verification_status <> 'rejected' or rejection_reason is not null)
);

comment on table public.driver_profiles is
  'One row per driver, created by an admin onboarding RPC. Row existence is '
  'the "is a driver" check; verification_status gates going online.';

-- PARTIAL unique index, not a table constraint. Body numbers must not collide
-- within a TODA, but several drivers may legitimately sit at null while their
-- numbers are pending, and a plain UNIQUE would let only one of them exist.
create unique index driver_profiles_zone_body_key
  on public.driver_profiles (toda_zone_id, body_number)
  where body_number is not null;

create index driver_profiles_status_idx on public.driver_profiles (verification_status);
create index driver_profiles_zone_idx   on public.driver_profiles (toda_zone_id);

alter table public.driver_profiles enable row level security;

create policy driver_profiles_select_own
  on public.driver_profiles for select
  using (id = auth.uid());

-- SELECT only for admins, deliberately not `for all`.
--
-- An `admin ... for all` policy would let an administrator PATCH
-- verification_status straight through PostgREST, approving a driver without
-- writing the admin_audit_logs row that .pipeline/specs.md requires for every
-- such change. That is not an RLS hole -- is_admin() is still a real check --
-- but it is an audit-integrity hole, and it was caught in review before this
-- table was written. Every mutation goes through a security definer RPC, which
-- executes as its owner and therefore needs no write policy here at all.
create policy driver_profiles_select_admin
  on public.driver_profiles for select
  using (public.is_admin(auth.uid()));
