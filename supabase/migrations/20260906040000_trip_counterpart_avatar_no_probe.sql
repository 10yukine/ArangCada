-- Fix: trip_counterpart_avatar_path() let a non-participant distinguish
-- "this trip exists" from "this trip doesn't exist".
--
-- Caught during review, before any external finding came
-- back -- recorded here the same way regardless, since it is a real
-- inconsistency against this repo's own established pattern.
--
-- The original body returned NULL silently when p_trip_id did not exist
-- at all, but raised a 42501 exception when the trip DID exist and the
-- caller simply was not one of its two participants. Those are two
-- different, distinguishable response shapes for the same caller-facing
-- question ("can I see this trip's counterpart photo?"), which lets any
-- authenticated caller probe whether an arbitrary trip_id is real by
-- watching which shape comes back -- a much smaller leak than a full row
-- (trip UUIDs are already unguessable v4 values, and nothing else about
-- the trip is disclosed either way), but still a real inconsistency
-- against the exact pattern this migration's own header cited as
-- precedent: 20260906020000_complaint_status_admin_scope.sql's
-- "select ... for update; if not found or not has_admin_scope(...)"
-- combines both cases into one response on purpose, specifically to avoid
-- this.
--
-- Fix: a non-participant now gets NULL too, identical to every other
-- "nothing to show" outcome this function already has (no counterpart,
-- counterpart has no photo, trip not in the live status window). This is
-- also a better fit for the feature's own "cosmetic, best-effort" design
-- than raising ever was -- the client's own catch-all around this call
-- already treats any thrown exception exactly the same as a null return
-- (falls back to initials), so nothing about legitimate behaviour changes.

create or replace function public.trip_counterpart_avatar_path(p_trip_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_uid uuid := auth.uid();
  v_counterpart_id uuid;
begin
  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (v_trip.rider_id <> v_uid and v_trip.driver_id <> v_uid) then
    return null;
  end if;
  if v_trip.status not in (
       'driver_assigned', 'accepted', 'driver_en_route',
       'arrived', 'in_progress', 'emergency_reported'
     ) then
    return null;
  end if;

  v_counterpart_id := case
    when v_trip.rider_id = v_uid then v_trip.driver_id
    else v_trip.rider_id
  end;
  if v_counterpart_id is null then
    return null;
  end if;

  return (select avatar_path from public.profiles where id = v_counterpart_id);
end;
$$;

comment on function public.trip_counterpart_avatar_path(uuid) is
  'Returns only the counterpart''s avatar_path (never a full profiles row), '
  'and only NULL -- never an exception -- for every case where there is '
  'nothing to show: trip not found, caller not a participant, trip not in '
  'the live status window, no counterpart, or no photo. Fixed 6 Sep 2026 '
  '(later still, cont. VI): the original raised on the not-a-participant '
  'case specifically, which let a caller distinguish it from '
  'trip-not-found -- see this migration''s header. Paired with '
  'profile_photos_select_trip_counterpart, which is what actually lets '
  'the caller sign a URL for the returned path.';

-- Grants are unchanged from 20260906030000; restated for clarity and to
-- survive a future drop/recreate, same convention as
-- 20260906020000_complaint_status_admin_scope.sql.
revoke execute on function public.trip_counterpart_avatar_path(uuid)
  from public, anon;
grant execute on function public.trip_counterpart_avatar_path(uuid)
  to authenticated, service_role;
