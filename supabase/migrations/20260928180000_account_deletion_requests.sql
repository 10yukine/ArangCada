-- Verified, one-use requests. A privacy officer reviews dependent trip and
-- incident records before removing the Auth user and personal profile data.
create table public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  email text not null,
  token_hash text not null unique,
  status text not null default 'pending_email'
    check (status in ('pending_email', 'confirmed', 'completed', 'rejected')),
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  confirmed_at timestamptz,
  notified_at timestamptz,
  completed_at timestamptz
);

create index account_deletion_requests_user_idx
  on public.account_deletion_requests(user_id, requested_at desc);

alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from public, anon, authenticated;
grant select, insert, update, delete on public.account_deletion_requests to service_role;
