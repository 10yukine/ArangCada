-- One application profile per Supabase Auth user.

create type public.user_role as enum ('commuter', 'driver', 'admin');
create type public.profile_status as enum ('active', 'suspended');

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  role         public.user_role      not null default 'commuter',
  display_name text                  not null,
  phone        text,
  status       public.profile_status not null default 'active',
  created_at   timestamptz           not null default now(),
  updated_at   timestamptz           not null default now()
);

comment on table public.profiles is
  'Application profile for each Supabase Auth user. Role drives dispatch and admin access.';

-- Admin checks run through a security-definer helper instead of a policy that
-- re-queries profiles. A policy on profiles that selects from profiles would
-- recurse infinitely.
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = uid
      and p.role = 'admin'
      and p.status = 'active'
  );
$$;

comment on function public.is_admin(uuid) is
  'True when the given user is an active admin. Security definer to avoid RLS recursion.';

alter table public.profiles enable row level security;

create policy profiles_select_own
  on public.profiles for select
  using (id = auth.uid());

create policy profiles_update_own
  on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_select_admin
  on public.profiles for select
  using (public.is_admin(auth.uid()));
