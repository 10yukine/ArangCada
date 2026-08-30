-- Push-token registry for the FCM-as-transport-only push layer.
--
-- Scope: Firebase Cloud Messaging is used ONLY to carry a push notification
-- to a device. Supabase remains authoritative for users, rides, dispatch,
-- fare, TODA boundaries, chat, and all business data -- this table exists
-- solely so a trusted server-side sender (a future Edge Function, once a
-- Firebase service-account credential is supplied out of band by the
-- project owner) knows which FCM token(s) belong to which authenticated
-- user. No Firestore, Firebase Auth, Firebase Storage, or Cloud Functions
-- are introduced by this migration.
--
-- NOT APPLIED: written and tested locally only. See
-- docs/COMPETITOR_TECH_DECISIONS.md and the FCM session notes for the
-- explicit approval boundary before this is pushed to any Supabase project.

create table public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  fcm_token text not null,
  platform text not null default 'android',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint push_tokens_platform_known check (platform in ('android', 'ios', 'web')),
  constraint push_tokens_token_length check (char_length(fcm_token) between 16 and 4096),
  unique (fcm_token)
);

create index push_tokens_user_idx on public.push_tokens (user_id);

alter table public.push_tokens enable row level security;

-- Owners may see their own registered devices (e.g. a "signed-in devices"
-- settings screen later); nobody may browse another user's tokens. Only a
-- trusted server-side sender (service_role, inside an Edge Function) reads
-- across users to actually dispatch a push.
create policy push_tokens_select_owner
  on public.push_tokens for select
  to authenticated
  using (user_id = (select auth.uid()));

grant select on public.push_tokens to authenticated;

-- register_push_token: idempotent upsert on the (user, token) pair, called
-- right after a token is minted or refreshed on the device. A token can
-- silently move between accounts on a shared/reused device (sign-out then a
-- different sign-in), so re-pointing an existing row to the current caller
-- is intentional rather than an application-writable free-for-all.
create or replace function public.register_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'unsupported push platform' using errcode = '22023';
  end if;

  insert into public.push_tokens (user_id, fcm_token, platform, updated_at)
  values (auth.uid(), trim(p_fcm_token), p_platform, now())
  on conflict (fcm_token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        updated_at = now();
end;
$$;

revoke execute on function public.register_push_token(text, text)
  from public, anon, authenticated;
grant execute on function public.register_push_token(text, text)
  to authenticated, service_role;

-- unregister_push_token: called on sign-out so a stale token on a shared
-- device does not keep receiving another account's ride-offer pushes.
create or replace function public.unregister_push_token(p_fcm_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.push_tokens
   where fcm_token = trim(p_fcm_token) and user_id = auth.uid();
end;
$$;

revoke execute on function public.unregister_push_token(text)
  from public, anon, authenticated;
grant execute on function public.unregister_push_token(text)
  to authenticated, service_role;
