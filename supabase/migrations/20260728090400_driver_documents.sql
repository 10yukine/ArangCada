-- Driver verification documents. The file itself lives in a private Supabase
-- Storage bucket; this table holds only the path and review state.

create type public.document_type as enum (
  'drivers_license',
  'or_cr',
  'toda_membership',
  'barangay_clearance',
  'vehicle_photo'
);

create type public.verification_status as enum ('pending', 'approved', 'rejected');

create table public.driver_documents (
  id               uuid primary key default gen_random_uuid(),
  driver_id        uuid not null references public.profiles (id) on delete cascade,
  document_type    public.document_type not null,
  storage_path     text not null,
  status           public.verification_status not null default 'pending',
  reviewed_by      uuid references public.profiles (id),
  reviewed_at      timestamptz,
  rejection_reason text,
  created_at       timestamptz not null default now(),
  constraint driver_documents_rejection_reason_required
    check (status <> 'rejected' or rejection_reason is not null)
);

comment on table public.driver_documents is
  'Verification document metadata only. Never store document contents or PII here.';

create index driver_documents_driver_idx on public.driver_documents (driver_id);
create index driver_documents_status_idx on public.driver_documents (status);

create unique index driver_documents_one_per_type
  on public.driver_documents (driver_id, document_type);

alter table public.driver_documents enable row level security;

-- A driver sees and uploads only their own documents. Admins review everything.
create policy driver_documents_select_own
  on public.driver_documents for select
  using (driver_id = auth.uid());

create policy driver_documents_insert_own
  on public.driver_documents for insert
  with check (driver_id = auth.uid());

create policy driver_documents_admin_all
  on public.driver_documents for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
