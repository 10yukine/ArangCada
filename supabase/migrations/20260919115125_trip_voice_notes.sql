-- Audio is immutable, participant-only, and readable only while chat is retained.
alter table public.trip_messages
  add column voice_path text,
  add column voice_duration_ms integer,
  add constraint trip_message_voice_valid check (
    (voice_path is null and voice_duration_ms is null) or
    (voice_path is not null and voice_duration_ms is not null and voice_duration_ms between 1 and 60000
      and voice_path = trip_id::text || '/' || sender_id::text || '/' || id::text || '.m4a')
  );
create unique index trip_messages_voice_path_idx on public.trip_messages(voice_path)
  where voice_path is not null;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('trip-voice-notes', 'trip-voice-notes', false, 1048576, array['audio/mp4'])
on conflict(id) do update set public = false, file_size_limit = 1048576,
  allowed_mime_types = array['audio/mp4'];

create policy trip_voice_upload on storage.objects for insert to authenticated
with check (
  bucket_id = 'trip-voice-notes'
  and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.m4a$'
  and split_part(name, '/', 2) = (select auth.uid())::text
  and exists (select 1 from public.trips t
    where t.id::text = split_part(name, '/', 1)
      and ((select auth.uid()) = t.rider_id or (select auth.uid()) = t.driver_id)
      and t.status in ('accepted','driver_en_route','arrived','in_progress','emergency_reported'))
);
create policy trip_voice_listen on storage.objects for select to authenticated
using (
  bucket_id = 'trip-voice-notes'
  and exists (select 1 from public.trip_messages m join public.trips t on t.id = m.trip_id
    where m.voice_path = storage.objects.name
      and ((select auth.uid()) = t.rider_id or (select auth.uid()) = t.driver_id)
      and (t.status in ('accepted','driver_en_route','arrived','in_progress','emergency_reported')
        or (t.status = 'completed' and t.completed_at >= now() - interval '30 days')))
);
-- No client UPDATE/DELETE policies: sent audio cannot be replaced or erased.

create function public.send_trip_voice_message(p_trip_id uuid, p_message_id uuid, p_duration_ms integer)
returns public.trip_messages
language plpgsql security definer set search_path = '' as $$
declare
  v_trip public.trips%rowtype;
  v_message public.trip_messages%rowtype;
  v_path text;
begin
  -- Same privileged insertion boundary as send_trip_message; no direct client inserts.
  -- Lock serializes sends with ride completion and concurrent retries.
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or auth.uid() is null
    or not (auth.uid() = v_trip.rider_id or auth.uid() = coalesce(v_trip.driver_id, v_trip.rider_id)) then
    raise exception 'trip participant required' using errcode = '42501';
  end if;
  if p_message_id is null or p_duration_ms is null or p_duration_ms not between 1 and 60000 then
    raise exception 'invalid voice note' using errcode = '22023';
  end if;
  if not (v_trip.status in ('accepted','driver_en_route','arrived','in_progress','emergency_reported')
    or (v_trip.status = 'completed' and coalesce(v_trip.completed_at >= now() - interval '30 days', false))) then
    raise exception 'trip chat is unavailable' using errcode = '22023';
  end if;
  v_path := p_trip_id::text || '/' || auth.uid()::text || '/' || p_message_id::text || '.m4a';
  select * into v_message from public.trip_messages where id = p_message_id;
  if found then
    if v_message.trip_id = p_trip_id and v_message.sender_id = auth.uid()
      and v_message.voice_path = v_path and v_message.voice_duration_ms = p_duration_ms then
      return v_message;
    end if;
    raise exception 'message id already used' using errcode = '22023';
  end if;
  if v_trip.status not in ('accepted','driver_en_route','arrived','in_progress','emergency_reported') then
    raise exception 'trip chat is closed' using errcode = '22023';
  end if;
  if not exists (select 1 from storage.objects
    where bucket_id = 'trip-voice-notes' and name = v_path
      and metadata->>'mimetype' = 'audio/mp4'
      and (metadata->>'size')::bigint between 1 and 1048576) then
    raise exception 'upload a valid voice note first' using errcode = '22023';
  end if;
  insert into public.trip_messages(id, trip_id, sender_id, body, voice_path, voice_duration_ms)
  values (p_message_id, p_trip_id, auth.uid(), 'Voice message', v_path, p_duration_ms)
  returning * into v_message;
  return v_message;
end;
$$;
revoke all on function public.send_trip_voice_message(uuid,uuid,integer) from public, anon;
grant execute on function public.send_trip_voice_message(uuid,uuid,integer) to authenticated;
