-- Trip-counterpart avatar visibility.
--
-- WHY THIS EXISTS
--
-- Profile photos shipped with a deliberately narrow Storage read
-- policy (profile_photos_select_own_or_admin) -- only the owner or an
-- admin can mint a signed URL for a given avatar_path. That was the right
-- default for a first pass, but it means a rider and their assigned
-- driver can never see each other's photo: the driver-matched card, the
-- active-trip screen, and the chat thread all fall back to initials only,
-- even once profiles.avatar_path is populated on both sides. Found during
-- the driver-side feature audit, 6 Sep 2026
--
-- SHAPE
--
-- Two pieces, layered the same way the rest of this Storage design already
-- works ("Storage RLS -- not the profiles column -- decides who may
-- actually read a path"):
--
-- 1. A narrow security-definer RPC that returns ONLY a path (never a full
--    profiles row -- profiles holds phone/email, which trip participants
--    must not see just because they share a ride; this is why
--    profiles_select_own/profiles_select_admin are not widened instead).
-- 2. A matching Storage RLS clause so the client's own createSignedUrl()
--    call (made with the caller's own JWT, against the Storage service,
--    independent of any RPC) is actually allowed to sign that path.
--
-- Deliberately scoped to only the trip statuses where a counterpart
-- currently exists and the ride is still live: driver_assigned (the
-- driver-matched card shows before acceptance) through emergency_reported.
-- completed is NOT included -- once a ride ends there is no ongoing reason
-- to keep exposing either party's photo to the other, and chat's own
-- read-only history window (30 days, client-side in
-- supabase_chat_repository.dart) already works fine showing initials only
-- for old conversations.

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
  if not found then
    return null;
  end if;
  if v_trip.rider_id <> v_uid and v_trip.driver_id <> v_uid then
    raise exception 'only a trip participant may look up the counterpart photo'
      using errcode = '42501';
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
  'Returns only the counterpart''s avatar_path (never a full profiles row) '
  'for a trip the caller actually participates in, and only while the ride '
  'is live -- see this migration''s header. Paired with '
  'profile_photos_select_trip_counterpart below, which is what actually '
  'lets the caller sign a URL for the returned path.';

revoke execute on function public.trip_counterpart_avatar_path(uuid)
  from public, anon;
grant execute on function public.trip_counterpart_avatar_path(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Storage: the matching read grant for whatever path the RPC above returns.
-- ---------------------------------------------------------------------------
create policy profile_photos_select_trip_counterpart
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and exists (
      select 1
        from public.trips t
       where t.status in (
               'driver_assigned', 'accepted', 'driver_en_route',
               'arrived', 'in_progress', 'emergency_reported'
             )
         and (
           (t.rider_id = (select auth.uid())
             and t.driver_id::text = (storage.foldername(name))[1])
           or
           (t.driver_id = (select auth.uid())
             and t.rider_id::text = (storage.foldername(name))[1])
         )
    )
  );
