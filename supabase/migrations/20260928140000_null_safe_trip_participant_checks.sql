-- Participant checks must not pass on a NULL driver.
--
-- Twelve trip RPCs guarded callers with `auth.uid() <> v_trip.driver_id` (or the
-- reverse). While a trip has no driver yet, driver_id is NULL, `<>` yields NULL,
-- and `if not found or (... and NULL)` does not raise -- so any signed-in user
-- who knew a trip id could cancel, expire, message, complain about or rate a
-- ride they are not part of, and the driver-only checks let anyone through.
-- rider_id is NOT NULL, so riders and assigned drivers are unaffected.
--
-- Each function below is its latest definition copied verbatim, with only the
-- auth.uid() comparisons switched to IS DISTINCT FROM (NULL-safe). Grants are
-- kept by CREATE OR REPLACE. Found by Open Code Review + security audit,
-- 28 Sep 2026. Regression: supabase/tests/83_null_driver_participant_test.sql.

-- accept_ride: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.accept_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the assigned driver can accept this ride'
      using errcode = '42501';
  end if;

  if v_trip.status = 'accepted' then
    return v_trip;
  end if;

  if v_trip.status <> 'driver_assigned'
     or v_trip.accept_by is null
     or clock_timestamp() > v_trip.accept_by then
    raise exception 'this ride offer is no longer available'
      using errcode = '22023';
  end if;

  if not public.can_driver_go_online(v_trip.driver_id)
     or exists (
       select 1 from public.driver_feedback_obligations
        where driver_id = v_trip.driver_id and submitted_at is null
     ) then
    raise exception 'the driver is no longer eligible to accept this booking'
      using errcode = '42501';
  end if;

  update public.trips
     set status = 'accepted', accepted_at = now(), updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.accepted');

  return v_trip;
end;
$$;

-- cancel_ride: from 20260928050000_driver_cancel_with_reason.sql
create or replace function public.cancel_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only a trip participant can cancel this ride'
      using errcode = '42501';
  end if;

  if auth.uid() = v_trip.driver_id then
    raise exception 'drivers cancel with cancel_ride_as_driver and a reason'
      using errcode = '42501';
  end if;

  if v_trip.status = 'cancelled_by_rider' then
    return v_trip;
  end if;

  if v_trip.status in ('completed', 'cancelled_by_rider', 'cancelled_by_driver', 'no_driver_available') then
    raise exception 'a closed trip cannot be cancelled again'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'cancelled_by_rider', cancellation_reason = 'cancelled_by_rider', updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  if v_trip.driver_id is not null then
    update public.driver_availability
       set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
     where driver_id = v_trip.driver_id;
  end if;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.cancelled_by_rider');

  return v_trip;
end;
$$;

-- complete_trip: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.complete_trip(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_settings public.app_evaluation_settings%rowtype;
  v_completed integer;
  v_due boolean;
  v_location public.driver_availability%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only a trip participant can complete this ride'
      using errcode = '42501';
  end if;

  if v_trip.status = 'completed' then
    return v_trip;
  end if;

  if v_trip.status <> 'in_progress' then
    raise exception 'only an in-progress trip can be completed'
      using errcode = '22023';
  end if;

  if auth.uid() = v_trip.rider_id then
    select * into v_location from public.driver_availability
     where driver_id = v_trip.driver_id;

    if v_trip.completion_available_at is null
       or clock_timestamp() < v_trip.completion_available_at
       or v_location.latitude is null
       or public.st_distancesphere(
            public.st_setsrid(
              public.st_makepoint(v_location.longitude, v_location.latitude), 4326
            ),
            v_trip.dropoff
          ) > 100 then
      raise exception 'commuter completion requires destination proximity and the full countdown'
        using errcode = '22023';
    end if;
  end if;

  update public.trips
     set status = 'completed',
         final_fare = fare_estimate,
         completed_at = now(),
         updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  update public.driver_availability
     set is_online = false, updated_at = now()
   where driver_id = v_trip.driver_id;

  select * into v_settings from public.app_evaluation_settings where id;
  select count(*)::integer into v_completed
    from public.trips
   where driver_id = v_trip.driver_id and status = 'completed';

  v_due := case
    when v_settings.repeat_feedback
      then mod(v_completed, v_settings.feedback_interval) = 0
    else v_completed = v_settings.feedback_interval
         and not exists (
           select 1 from public.driver_feedback_obligations
            where driver_id = v_trip.driver_id
         )
  end;

  if v_due then
    insert into public.driver_feedback_obligations (trip_id, driver_id, toda_zone_id)
    values (v_trip.id, v_trip.driver_id, v_trip.toda_zone_id)
    on conflict (trip_id) do nothing;
  end if;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (
    v_trip.id,
    auth.uid(),
    'ride.completed',
    jsonb_build_object('feedback_due', v_due)
  );

  return v_trip;
end;
$$;

-- create_complaint: from 20260905020000_complaints.sql
create or replace function public.create_complaint(
  p_trip_id uuid,
  p_category text,
  p_description text,
  p_idempotency_key text
)
returns public.complaints
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_complaint public.complaints%rowtype;
  v_complainant public.profiles%rowtype;
  v_role text;
  v_respondent uuid;
  v_respondent_name text;
begin
  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'a complaint idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_complaint from public.complaints
   where idempotency_key = p_idempotency_key;

  if found then
    if v_complaint.complainant_id is distinct from auth.uid() or v_complaint.trip_id <> p_trip_id then
      raise exception 'that complaint key belongs to another report'
        using errcode = '42501';
    end if;
    return v_complaint;
  end if;

  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only a trip participant can file a complaint about it'
      using errcode = '42501';
  end if;

  -- Unlike SOS, a complaint is commonly filed AFTER the trip ends ("driver
  -- was late" only makes sense in hindsight), so every status is allowed
  -- except the ones where no ride actually happened.
  if v_trip.status in ('requested', 'searching_driver', 'cancelled_by_rider',
                        'cancelled_by_driver', 'no_driver_available') then
    raise exception 'a complaint requires a trip that actually had a driver assigned'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_description, '')), '') is null
     or char_length(trim(p_description)) > 500 then
    raise exception 'a complaint description is required'
      using errcode = '22023';
  end if;

  select * into v_complainant from public.profiles where id = auth.uid();

  if auth.uid() = v_trip.driver_id then
    v_role := 'driver';
    v_respondent := v_trip.rider_id;
    v_respondent_name := v_trip.rider_display_name;
  else
    v_role := 'commuter';
    v_respondent := v_trip.driver_id;
    v_respondent_name := v_trip.driver_display_name;
  end if;

  if v_respondent is null then
    raise exception 'this trip has no other participant to complain about'
      using errcode = '22023';
  end if;

  insert into public.complaints (
    trip_id, toda_zone_id, complainant_id, complainant_role,
    complainant_display_name, respondent_id, respondent_display_name,
    toda_name, category, description, idempotency_key
  )
  values (
    p_trip_id,
    v_trip.toda_zone_id,
    v_complainant.id,
    v_role,
    v_complainant.display_name,
    v_respondent,
    v_respondent_name,
    v_trip.toda_name,
    trim(p_category),
    trim(p_description),
    p_idempotency_key
  )
  returning * into v_complaint;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'complaint.filed');

  return v_complaint;
end;
$$;

-- create_sos_report: from 20260825170000_live_connected_remote_reconciliation.sql
create or replace function public.create_sos_report(
  p_trip_id uuid,
  p_reason text,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_meters double precision,
  p_idempotency_key text
)
returns public.sos_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_report public.sos_reports%rowtype;
  v_reporter public.profiles%rowtype;
begin
  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'an SOS idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_report from public.sos_reports
   where idempotency_key = p_idempotency_key;

  if found then
    if v_report.reporter_id is distinct from auth.uid() or v_report.trip_id <> p_trip_id then
      raise exception 'that SOS key belongs to another report'
        using errcode = '42501';
    end if;
    return v_report;
  end if;

  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only an active trip participant can send an SOS'
      using errcode = '42501';
  end if;

  if v_trip.status not in (
    'driver_assigned', 'accepted', 'driver_en_route',
    'arrived', 'in_progress', 'emergency_reported'
  ) then
    raise exception 'SOS reports require an active assigned trip'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null
     or char_length(trim(p_reason)) > 300 then
    raise exception 'a safety-report reason is required'
      using errcode = '22023';
  end if;

  if (p_lat is null) <> (p_lng is null)
     or (p_lat is not null and p_lat not between -90 and 90)
     or (p_lng is not null and p_lng not between -180 and 180)
     or (p_accuracy_meters is not null and p_accuracy_meters < 0) then
    raise exception 'an SOS location must contain one valid latitude/longitude snapshot'
      using errcode = '22023';
  end if;

  select * into v_reporter from public.profiles where id = auth.uid();

  insert into public.sos_reports (
    trip_id, toda_zone_id, reporter_id, reporter_role,
    reporter_display_name, driver_display_name, toda_name, reason,
    latitude, longitude, accuracy_meters, idempotency_key
  )
  values (
    p_trip_id,
    v_trip.toda_zone_id,
    v_reporter.id,
    case when v_reporter.id = v_trip.driver_id then 'driver' else 'commuter' end,
    v_reporter.display_name,
    v_trip.driver_display_name,
    v_trip.toda_name,
    trim(p_reason),
    p_lat,
    p_lng,
    p_accuracy_meters,
    p_idempotency_key
  )
  returning * into v_report;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'safety.sos_reported');

  return v_report;
end;
$$;

-- expire_ride: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.expire_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only a trip participant can close an expired request'
      using errcode = '42501';
  end if;
  if v_trip.status = 'no_driver_available' then
    return v_trip;
  end if;
  if (v_trip.status = 'driver_assigned' and clock_timestamp() < v_trip.accept_by)
     or (v_trip.status = 'searching_driver'
         and clock_timestamp() < v_trip.requested_at + interval '3 minutes')
     or v_trip.status not in ('driver_assigned', 'searching_driver') then
    raise exception 'the ride request has not expired'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'no_driver_available', updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  if v_trip.driver_id is not null then
    update public.driver_availability
       set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
     where driver_id = v_trip.driver_id;
  end if;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.expired');

  return v_trip;
end;
$$;

-- mark_arrived: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.mark_arrived(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the assigned driver can report arrival'
      using errcode = '42501';
  end if;
  if v_trip.status = 'arrived' then
    return v_trip;
  end if;
  if v_trip.status not in ('accepted', 'driver_en_route') then
    raise exception 'arrival requires an accepted ride'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'arrived', arrived_at = now(), updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.arrived');

  return v_trip;
end;
$$;

-- publish_driver_location: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.publish_driver_location(
  p_trip_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy_meters double precision
)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_result public.driver_availability%rowtype;
  v_distance double precision;
begin
  select * into v_trip from public.trips where id = p_trip_id;

  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the assigned driver can publish this trip location'
      using errcode = '42501';
  end if;

  if v_trip.status not in (
    'driver_assigned', 'accepted', 'driver_en_route',
    'arrived', 'in_progress', 'emergency_reported'
  ) then
    raise exception 'driver GPS is published only for an active assigned trip'
      using errcode = '22023';
  end if;

  if p_lat is null or p_lng is null
     or p_lat not between -90 and 90
     or p_lng not between -180 and 180
     or (p_accuracy_meters is not null and p_accuracy_meters < 0) then
    raise exception 'valid current driver GPS coordinates are required'
      using errcode = '22023';
  end if;

  update public.driver_availability
     set latitude = p_lat,
         longitude = p_lng,
         accuracy_meters = p_accuracy_meters,
         updated_at = now()
   where driver_id = v_trip.driver_id
   returning * into v_result;

  if not found then
    raise exception 'the assigned driver has no availability record'
      using errcode = 'P0002';
  end if;

  if v_trip.status = 'in_progress' and v_trip.completion_available_at is null then
    v_distance := public.st_distancesphere(
      public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326),
      v_trip.dropoff
    );

    if v_distance <= 100 then
      update public.trips
         set completion_available_at = now() + interval '60 seconds',
             updated_at = now()
       where id = p_trip_id and completion_available_at is null;

      if found then
        insert into public.trip_events (trip_id, actor_id, event_type)
        values (p_trip_id, auth.uid(), 'ride.destination_radius_entered');
      end if;
    end if;
  end if;

  return v_result;
end;
$$;

-- report_trip_chat: from 20260825170000_live_connected_remote_reconciliation.sql
create or replace function public.report_trip_chat(
  p_trip_id uuid,
  p_reason text,
  p_consent boolean
)
returns public.reported_trip_chats
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_report public.reported_trip_chats%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only a trip participant can report the private conversation'
      using errcode = '42501';
  end if;

  if p_consent is distinct from true then
    raise exception 'explicit consent is required before sharing chat with the LGU'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_reason, '')), '') is null
     or char_length(trim(p_reason)) > 500 then
    raise exception 'a concise chat-report reason is required'
      using errcode = '22023';
  end if;

  insert into public.reported_trip_chats (trip_id, reporter_id, reason, messages)
  select
    p_trip_id,
    auth.uid(),
    trim(p_reason),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', m.id,
          'sender_id', m.sender_id,
          'body', m.body,
          'created_at', m.created_at
        ) order by m.created_at
      ) filter (where m.id is not null),
      '[]'::jsonb
    )
    from public.trip_messages m
   where m.trip_id = p_trip_id
  returning * into v_report;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'chat.reported_with_consent');

  return v_report;
end;
$$;

-- send_trip_message: from 20260825170000_live_connected_remote_reconciliation.sql
create or replace function public.send_trip_message(
  p_trip_id uuid,
  p_body text
)
returns public.trip_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_message public.trip_messages%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
    raise exception 'only the rider and assigned driver can use trip chat'
      using errcode = '42501';
  end if;

  if v_trip.status not in (
    'accepted', 'driver_en_route', 'arrived', 'in_progress', 'emergency_reported'
  ) then
    raise exception 'trip chat opens after acceptance and closes when the ride ends'
      using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_body, '')), '') is null
     or char_length(trim(p_body)) > 1000 then
    raise exception 'a trip message must contain between 1 and 1000 characters'
      using errcode = '22023';
  end if;

  insert into public.trip_messages (trip_id, sender_id, body)
  values (p_trip_id, auth.uid(), trim(p_body))
  returning * into v_message;

  return v_message;
end;
$$;

-- start_trip: from 20260825133421_live_connected_vertical_slice.sql
create or replace function public.start_trip(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;
  if not found or v_trip.driver_id is distinct from auth.uid() then
    raise exception 'only the assigned driver can start this trip'
      using errcode = '42501';
  end if;
  if v_trip.status = 'in_progress' then
    return v_trip;
  end if;
  if v_trip.status <> 'arrived' then
    raise exception 'the driver must arrive before starting the trip'
      using errcode = '22023';
  end if;

  update public.trips
     set status = 'in_progress', started_at = now(), updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.started');

  return v_trip;
end;
$$;

-- submit_trip_rating: from 20260905030000_trip_ratings.sql
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
  if not found or (auth.uid() is distinct from v_trip.rider_id and auth.uid() is distinct from v_trip.driver_id) then
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
