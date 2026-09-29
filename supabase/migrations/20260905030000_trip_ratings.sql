-- Trip ratings: persisted, both directions, LGU-visible.
--
-- WHY THIS EXISTS
--
-- rating_screen.dart and driver_rating_screen.dart already have full UI and
-- call DemoState.submitTripRating() / submitDriverTripRating() -- in-memory
-- only. Every star and comment was gone on app restart, invisible to the
-- driver's record, and invisible to LGU/TODA, who explicitly need to see
-- both directions (owner decision, 5 Sep 2026).
--
-- WHY A NEW TABLE, NOT NEW trips COLUMNS
--
-- The owner also decided (5 Sep 2026) that a rating's comment is LGU-only --
-- neither trip party may read what the other wrote about them. trips is a
-- single row both the rider and the driver already have SELECT access to
-- (each needs their own fare, status, etc.), so a column on that row cannot
-- be hidden from one party without hiding it from both -- Postgres RLS is
-- row-level, not value-level, and this schema does not use column-level
-- privilege tricks anywhere else. A separate table with its own RLS -- the
-- same reasoning sos_reports and complaints already use -- is the only
-- clean way to keep one party's comment unreadable by the other while both
-- keep reading the trip.

create table public.trip_ratings (
  id                 uuid primary key default gen_random_uuid(),
  trip_id            uuid not null references public.trips (id),
  toda_zone_id       uuid not null references public.toda_zones (id),
  toda_name          text not null,
  rater_id           uuid not null references public.profiles (id),
  rater_role         text not null check (rater_role in ('commuter', 'driver')),
  rater_display_name text not null,
  ratee_id           uuid not null references public.profiles (id),
  ratee_display_name text not null,
  stars              smallint not null check (stars between 1 and 5),
  comment            text check (comment is null or char_length(comment) <= 240),
  created_at         timestamptz not null default now(),
  unique (trip_id, rater_role)
);

create index trip_ratings_zone_created_idx on public.trip_ratings (toda_zone_id, created_at desc);
create index trip_ratings_ratee_idx on public.trip_ratings (ratee_id);

comment on table public.trip_ratings is
  'One row per (trip, rater direction) -- the unique constraint is the '
  'dedupe key, not an idempotency_key column, because a rating has no '
  'legitimate reason to be safely retried with a changed value. The ratee '
  '(person being rated) has no read access to their own row here; only the '
  'rater and a scoped admin do -- see the RLS policy below. Display names '
  'are denormalised from trips.rider_display_name/driver_display_name at '
  'submission time, matching how sos_reports and complaints already do it.';

alter table public.trip_ratings enable row level security;

create policy trip_ratings_select_own_or_scoped_admin
  on public.trip_ratings for select
  to authenticated
  using (
    rater_id = (select auth.uid())
    or public.has_admin_scope((select auth.uid()), toda_zone_id)
  );

-- No insert/update policy: submit_trip_rating() below is the only writer,
-- security definer. Ratings are also never updated after insert -- there is
-- no update RPC at all, by design (see the RPC's "already rated" refusal).

create or replace function public.submit_trip_rating(
  p_trip_id uuid,
  p_stars integer,
  p_comment text
)
returns public.trip_ratings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_rating public.trip_ratings%rowtype;
  v_role text;
  v_ratee uuid;
  v_rater_name text;
  v_ratee_name text;
  v_comment text;
begin
  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
    raise exception 'only a trip participant can rate it'
      using errcode = '42501';
  end if;

  if v_trip.status <> 'completed' then
    raise exception 'only a completed trip can be rated'
      using errcode = '22023';
  end if;

  if p_stars is null or p_stars not between 1 and 5 then
    raise exception 'stars must be between 1 and 5'
      using errcode = '22023';
  end if;

  v_comment := nullif(trim(coalesce(p_comment, '')), '');
  if v_comment is not null and char_length(v_comment) > 240 then
    raise exception 'the comment is too long'
      using errcode = '22023';
  end if;

  if auth.uid() = v_trip.driver_id then
    v_role := 'driver';
    v_ratee := v_trip.rider_id;
    v_rater_name := v_trip.driver_display_name;
    v_ratee_name := v_trip.rider_display_name;
  else
    v_role := 'commuter';
    v_ratee := v_trip.driver_id;
    v_rater_name := v_trip.rider_display_name;
    v_ratee_name := v_trip.driver_display_name;
  end if;

  if v_ratee is null then
    raise exception 'this trip has no other participant to rate'
      using errcode = '22023';
  end if;

  if exists (
    select 1 from public.trip_ratings
     where trip_id = p_trip_id and rater_role = v_role
  ) then
    raise exception 'you have already rated this trip'
      using errcode = '22023';
  end if;

  insert into public.trip_ratings (
    trip_id, toda_zone_id, toda_name, rater_id, rater_role,
    rater_display_name, ratee_id, ratee_display_name, stars, comment
  )
  values (
    p_trip_id, v_trip.toda_zone_id, v_trip.toda_name, auth.uid(), v_role,
    v_rater_name, v_ratee, v_ratee_name, p_stars, v_comment
  )
  returning * into v_rating;

  return v_rating;
end;
$$;

comment on function public.submit_trip_rating(uuid, integer, text) is
  'Rates the other participant on a completed trip. Direction is derived '
  'server-side from which id matches auth.uid(). Raises rather than '
  'upserting on a repeat attempt for the same (trip, direction) -- there is '
  'no update path, by design.';

revoke execute on function public.submit_trip_rating(uuid, integer, text)
  from public, anon, authenticated;
grant execute on function public.submit_trip_rating(uuid, integer, text)
  to authenticated, service_role;
