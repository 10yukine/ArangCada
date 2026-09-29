-- Audit trail for privileged administrative actions.
--
-- Every promote, demote, approve, reject, suspend, and unsuspend writes
-- exactly one row here. That is a stated success criterion, and it is the
-- reason driver_profiles and profiles both
-- refuse direct writes from an authenticated session: a raw PATCH would change
-- the state without leaving a trace, which is precisely what an audit log is
-- for.
--
-- WHY THE PII CONSTRAINT IS A CHECK AND NOT A CONVENTION
--
-- project policy forbids logging names, phone numbers, and licence IDs. A
-- rule written only in prose survives exactly as long as everyone remembers
-- it; an audit log is a tempting place to stash "helpful context" and the
-- reviewer who would catch it may not exist. Encoding the prohibition as a
-- check constraint means the database refuses the row instead.
--
-- The constraint covers the specific keys that would carry identity. It cannot
-- stop someone burying a phone number inside a free-text reason, and it is not
-- meant to -- it removes the easy, structured mistake, which is the one that
-- would otherwise happen by default.

create table public.admin_audit_logs (
  id                uuid primary key default gen_random_uuid(),
  actor_id          uuid not null references public.profiles (id),
  action            text not null,
  target_profile_id uuid references public.profiles (id),
  reason            text,
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  constraint admin_audit_logs_metadata_no_pii
    check (
      not (
        metadata ? 'phone'
        or metadata ? 'email'
        or metadata ? 'display_name'
        or metadata ? 'license_number'
        or metadata ? 'member_name'
      )
    )
);

comment on table public.admin_audit_logs is
  'Immutable record of privileged admin actions. Written only by security '
  'definer RPCs -- there is no insert policy, so no session can forge or '
  'suppress an entry.';

comment on column public.admin_audit_logs.metadata is
  'Structured context for the action. A check constraint rejects identity-'
  'bearing keys; reference other rows by uuid instead.';

create index admin_audit_logs_actor_idx  on public.admin_audit_logs (actor_id, created_at desc);
create index admin_audit_logs_target_idx on public.admin_audit_logs (target_profile_id, created_at desc);
create index admin_audit_logs_action_idx on public.admin_audit_logs (action, created_at desc);

alter table public.admin_audit_logs enable row level security;

create policy admin_audit_logs_select_admin
  on public.admin_audit_logs for select
  using (public.is_admin(auth.uid()));

-- No insert, update, or delete policy for anyone, admins included.
--
-- Insert happens only inside security definer RPCs, which run as the function
-- owner rather than the calling session and so bypass RLS. An admin who could
-- insert directly could fabricate an entry; one who could update or delete
-- could erase their own. Neither is a capability an audit log should offer,
-- and neither is needed by any feature.
