-- Ride-tracking links a commuter can share with family or friends.
--
-- Calamba City Hall, 31 August 2026. Requested so a parent or spouse can watch
-- a trip in real time and know their person arrived. It also partly answers the
-- "fake booking, then an unsafe drop-off point" scenario City Hall raised in
-- the same meeting: an outside observer on the live route is a deterrent.
--
-- ============================================================================
-- READ THIS BEFORE CHANGING ANYTHING IN THIS FILE
-- ============================================================================
--
-- This is the FIRST and ONLY deliberately public read path in ArangCada.
-- Everything else in this schema is reachable only by an authenticated user
-- through RLS. Here, by design, an anonymous stranger with a URL gets data
-- back. That makes this file the highest-risk surface in the project, and it
-- is built defensively:
--
--   1. RLS on ride_share_links denies EVERYTHING to anon, including select.
--      The token table itself is never readable. There is no policy that
--      grants anon a row. Possessing a token does not let you enumerate
--      tokens, trips, or anything else.
--
--   2. The only anon-reachable entry point is ONE security-definer function
--      that takes a token and returns a fixed, hand-written column list. It
--      does not return a row type, does not `select *`, and cannot start
--      leaking a newly added trips column by accident -- a future migration
--      that adds a sensitive column to trips will not appear here unless
--      someone deliberately types it in.
--
--   3. Expiry is evaluated inside that function against the trip's own current
--      status. It is not a timestamp the client can read past and it is not
--      enforced by the app. A completed trip returns zero rows to a valid,
--      unrevoked token.
--
--   4. The payload carries NO rider identity, NO phone, NO email, NO address,
--      NO chat, NO payment data, NO trip history, and NO GPS trail -- only the
--      single current position point. Under RA 10173 this is the minimum
--      necessary to serve the stated purpose, and it is what
--      docs/legal/PRIVACY_POLICY.md section 6a discloses.
--
-- Widening this payload requires a documented design review.
--
-- ============================================================================

create table public.ride_share_links (
  -- 64 hex characters from two gen_random_uuid() calls: ~244 bits of entropy,
  -- unguessable by brute force. gen_random_uuid() is core PostgreSQL 13+, so
  -- this does not depend on pgcrypto being present in a particular schema --
  -- which matters because this function runs with search_path = ''.
  token       text primary key
    default replace(gen_random_uuid()::text, '-', '')
         || replace(gen_random_uuid()::text, '-', ''),
  trip_id     uuid not null references public.trips (id) on delete cascade,
  created_by  uuid not null references public.profiles (id),
  created_at  timestamptz not null default now(),
  revoked_at  timestamptz,
  constraint ride_share_links_token_length check (char_length(token) between 32 and 128)
);

create index ride_share_links_trip_idx on public.ride_share_links (trip_id);

comment on table public.ride_share_links is
  'Unguessable tokens letting a commuter share live tracking of one active trip. '
  'RLS denies anon entirely; the only public read path is ride_share_view(). '
  'Requested by Calamba City Hall, 31 Aug 2026.';

alter table public.ride_share_links enable row level security;

-- The commuter who created the link can see and revoke their own links.
-- Note there is no policy granting anon anything at all.
create policy ride_share_links_select_own
  on public.ride_share_links for select
  to authenticated
  using (created_by = (select auth.uid()));

create policy ride_share_links_update_own
  on public.ride_share_links for update
  to authenticated
  using (created_by = (select auth.uid()))
  with check (created_by = (select auth.uid()));

-- No insert policy: links are minted only through create_ride_share_link(),
-- which verifies trip ownership. No delete policy: revocation is an update, so
-- an issued token stays auditable rather than vanishing.

-- ---------------------------------------------------------------------------
-- Minting
-- ---------------------------------------------------------------------------

create or replace function public.create_ride_share_link(p_trip_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_trip  public.trips%rowtype;
  v_token text;
begin
  select * into v_trip
    from public.trips
   where id = p_trip_id;

  if not found or v_trip.rider_id <> auth.uid() then
    raise exception 'that trip does not belong to you'
      using errcode = '42501';
  end if;

  -- Only an in-flight trip is shareable. Minting a token for a finished trip
  -- would create a link that returns nothing, which is merely useless -- but
  -- minting one for a *future* trip would be a standing window into the
  -- commuter's movements, which is not.
  if v_trip.status in ('completed', 'cancelled_by_rider', 'cancelled_by_driver',
                       'no_driver_available') then
    raise exception 'this trip has already ended'
      using errcode = '22023';
  end if;

  -- Reuse the live token for a trip rather than minting a second one, so a
  -- commuter who taps Share twice does not leave an extra valid link loose.
  select token into v_token
    from public.ride_share_links
   where trip_id = p_trip_id and revoked_at is null
   limit 1;

  if v_token is not null then
    return v_token;
  end if;

  insert into public.ride_share_links (trip_id, created_by)
  values (p_trip_id, v_trip.rider_id)
  returning token into v_token;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (p_trip_id, v_trip.rider_id, 'ride.share_link_created', '{}'::jsonb);

  return v_token;
end;
$$;

comment on function public.create_ride_share_link(uuid) is
  'Mints (or returns the existing) share token for the caller''s own active trip.';

revoke execute on function public.create_ride_share_link(uuid) from public, anon;
grant execute on function public.create_ride_share_link(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Revocation
-- ---------------------------------------------------------------------------

create or replace function public.revoke_ride_share_link(p_trip_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_count integer;
begin
  update public.ride_share_links l
     set revoked_at = now()
    from public.trips t
   where l.trip_id = p_trip_id
     and l.trip_id = t.id
     and t.rider_id = auth.uid()
     and l.revoked_at is null;

  get diagnostics v_count = row_count;

  if v_count > 0 then
    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    values (p_trip_id, auth.uid(), 'ride.share_link_revoked', '{}'::jsonb);
  end if;

  return v_count;
end;
$$;

comment on function public.revoke_ride_share_link(uuid) is
  'Immediately invalidates any live share token for the caller''s own trip.';

revoke execute on function public.revoke_ride_share_link(uuid) from public, anon;
grant execute on function public.revoke_ride_share_link(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The public read path
-- ---------------------------------------------------------------------------
--
-- Every column below was chosen deliberately. What is ABSENT is the important
-- part, and the list is repeated here so a reviewer does not have to diff it
-- against the trips table to find out:
--
--   rider_id, rider_display_name  -- the person being tracked is not named
--   any phone number or email     -- not in the payload, not in trips
--   fare, payment_method          -- a tracker has no business seeing money
--   chat messages                 -- separate table, never joined here
--   trip history                  -- one trip, by one token
--   a location trail              -- one current point, no history
--
-- driver_availability holds the driver's last reported fix. It is the closest
-- thing to a live position in the current schema; request_ride sets is_online
-- false on assignment but does not clear the coordinates, so the fix keeps
-- being useful through the trip. position_updated_at is returned so the
-- viewer can judge staleness for themselves rather than being shown a stale
-- dot presented as current.

create or replace function public.ride_share_view(p_token text)
returns table (
  status              text,
  pickup_label        text,
  destination_label   text,
  driver_display_name text,
  driver_body_number  text,
  toda_name           text,
  pickup_lat          double precision,
  pickup_lng          double precision,
  destination_lat     double precision,
  destination_lng     double precision,
  driver_lat          double precision,
  driver_lng          double precision,
  position_updated_at timestamptz,
  requested_at        timestamptz
)
language sql
stable
security definer
set search_path to ''
as $$
  select
    t.status::text,
    t.pickup_label,
    t.destination_label,
    t.driver_display_name,
    dp.body_number,
    t.toda_name,
    t.pickup_lat,
    t.pickup_lng,
    t.destination_lat,
    t.destination_lng,
    da.latitude,
    da.longitude,
    da.updated_at,
    t.requested_at
  from public.ride_share_links l
  join public.trips t on t.id = l.trip_id
  left join public.driver_profiles dp on dp.id = t.driver_id
  left join public.driver_availability da on da.driver_id = t.driver_id
  where l.token = p_token
    and l.revoked_at is null
    -- Expiry at trip end, enforced here and nowhere else.
    and t.status not in ('completed', 'cancelled_by_rider', 'cancelled_by_driver',
                         'no_driver_available');
$$;

comment on function public.ride_share_view(text) is
  'The only anon-reachable read path in ArangCada. Returns live tracking for one '
  'active trip given its share token, and zero rows once that trip ends or the '
  'token is revoked. Carries no rider identity, contact details, fare, chat, or '
  'location history -- see docs/legal/PRIVACY_POLICY.md section 6a. Widening '
  'this payload requires a documented design review.';

-- anon is granted execute deliberately: a family member without an ArangCada
-- account is the entire point of the feature. anon gets THIS function and
-- nothing else.
revoke execute on function public.ride_share_view(text) from public;
grant execute on function public.ride_share_view(text) to anon, authenticated, service_role;
