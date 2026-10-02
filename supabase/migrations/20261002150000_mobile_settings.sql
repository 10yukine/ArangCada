-- Three things the owner can change for every phone without a new build
-- (release audit, 2 Oct 2026).
--
-- min_mobile_build: the oldest mobile build the server still accepts.
--   The Android app is installed by hand from an APK, so an old build stays in
--   use until its owner replaces it. Some server changes break old builds
--   outright: switching on CAPTCHA, or moving the verification code from email
--   to SMS. A build older than this number shows only an "Update ArangCada"
--   screen. 0 accepts every build. Use the number after "+" in the build's
--   version. Raise it when no trip is open: a driver who restarts mid-trip on
--   a retired build cannot finish that trip in the app.
--
-- routing: which service draws road routes.
--   'google'   Google Routes first, openrouteservice if Google has none.
--   'ors'      openrouteservice first, Google Routes if it has none.
--   'ors_only' Google Routes is never called.
--
-- search: which service answers place search.
--   'google'   Google Places, MapTiler when Google is unavailable.
--   'maptiler' Google Places is never called.
--
-- Google bills per request, so the last two are the cost switches. In the SQL
-- editor:
--   update public.mobile_settings set routing = 'ors_only', search = 'maptiler';
--
-- The app asks when it starts and when it returns to the foreground
-- (app/mobile_settings.dart). No answer means "accept this build, Google
-- first", so a failure here never locks anyone out, and builds that predate
-- this are not affected.
--
-- Its own table, with no policy: a wrong value can lock every user out, so no
-- account can change it through the API, administrators included. (An admin
-- can edit dispatch_settings directly, which is why these are not columns
-- there.)
create table public.mobile_settings (
  id               boolean primary key default true check (id),
  min_mobile_build integer not null default 0 check (min_mobile_build >= 0),
  routing          text not null default 'google'
    check (routing in ('google', 'ors', 'ors_only')),
  search           text not null default 'google'
    check (search in ('google', 'maptiler'))
);

comment on table public.mobile_settings is
  'One row, changed only in the SQL editor: the oldest accepted mobile build and which routing and search services the app uses. Read through get_mobile_settings().';

insert into public.mobile_settings default values;

alter table public.mobile_settings enable row level security;
revoke all on public.mobile_settings from anon, authenticated;

-- The app has to ask before sign-in: a retired build may be one that can no
-- longer sign in.
create function public.get_mobile_settings()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'min_mobile_build', s.min_mobile_build,
           'routing', s.routing,
           'search', s.search)
    from public.mobile_settings s
   where s.id;
$$;

revoke execute on function public.get_mobile_settings() from public;
grant execute on function public.get_mobile_settings() to anon, authenticated;
