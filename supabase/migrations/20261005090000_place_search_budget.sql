-- A daily place-search budget for each verified account.
--
-- Place search now goes through the place-search Edge Function, so the
-- LocationIQ key stays on the server instead of inside the app. The provider's
-- free plan allows 5,000 requests a day for the whole project. Without a
-- budget, one signed-in account could use them all and leave every other
-- rider with no search.
--
-- consume_place_search() is called by that function with the caller's own
-- JWT. It answers true and counts one search, or false when the caller is not
-- a verified account or has used the day's budget. A day is a UTC day.
--
-- Regression: supabase/tests/96_place_search_budget_test.sql

create table public.place_search_usage (
  user_id  uuid not null references public.profiles (id) on delete cascade,
  day      date not null default current_date,
  requests integer not null default 0 check (requests >= 0),
  primary key (user_id, day)
);

comment on table public.place_search_usage is
  'Place searches made by each account per UTC day. Counts only: no search text is stored.';

-- Read and written only through consume_place_search().
alter table public.place_search_usage enable row level security;
revoke all on public.place_search_usage from anon, authenticated;

create or replace function public.consume_place_search()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- A booking needs a handful of searches. 300 leaves room for a long day of
  -- use while keeping one account to a small share of the 5,000.
  c_daily_budget constant integer := 300;
  v_uid uuid := auth.uid();
  v_requests integer;
begin
  if v_uid is null or not public.is_verified_account(v_uid) then
    return false;
  end if;

  -- ponytail: old days are cleared here instead of by a scheduled job; the
  -- table holds at most two rows per account. Add a job if it ever grows.
  delete from public.place_search_usage where day < current_date - 1;

  insert into public.place_search_usage as usage (user_id, day, requests)
  values (v_uid, current_date, 1)
  on conflict (user_id, day) do update set requests = usage.requests + 1
  returning requests into v_requests;

  return v_requests <= c_daily_budget;
end;
$$;

revoke all on function public.consume_place_search() from public, anon;
grant execute on function public.consume_place_search() to authenticated;
