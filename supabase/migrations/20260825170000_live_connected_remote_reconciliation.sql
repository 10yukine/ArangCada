-- Reconcile an out-of-band remote application that captured the connected
-- migration before its chat/SOS/evaluation/admin tail had been written.
-- Every replayed function uses CREATE OR REPLACE. The existing scoped document
-- policy is rebuilt so this migration also runs after a complete local chain.

drop policy if exists driver_documents_select_scoped_toda
  on public.driver_documents;
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
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
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
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
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
    if v_report.reporter_id <> auth.uid() or v_report.trip_id <> p_trip_id then
      raise exception 'that SOS key belongs to another report'
        using errcode = '42501';
    end if;
    return v_report;
  end if;

  select * into v_trip from public.trips where id = p_trip_id;
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
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

create or replace function public.update_sos_status(
  p_report_id uuid,
  p_status text,
  p_note text
)
returns public.sos_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_report public.sos_reports%rowtype;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can update an SOS case'
      using errcode = '42501';
  end if;

  if p_status not in ('acknowledged', 'investigating', 'escalated', 'resolved', 'dismissed') then
    raise exception 'unknown safety-case status'
      using errcode = '22023';
  end if;

  select * into v_report from public.sos_reports where id = p_report_id for update;
  if not found then
    raise exception 'the safety report does not exist'
      using errcode = 'P0002';
  end if;
  if v_report.status in ('resolved', 'dismissed') and v_report.status <> p_status then
    raise exception 'a closed safety report cannot be reopened through this action'
      using errcode = '22023';
  end if;

  update public.sos_reports
     set status = p_status,
         admin_note = nullif(trim(coalesce(p_note, '')), ''),
         updated_at = now()
   where id = p_report_id
   returning * into v_report;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    auth.uid(),
    'safety.' || p_status,
    v_report.reporter_id,
    jsonb_build_object('report_id', v_report.id, 'trip_id', v_report.trip_id)
  );

  return v_report;
end;
$$;

create or replace function public.submit_driver_feedback(
  p_trip_id uuid,
  p_answers jsonb,
  p_comment text,
  p_anonymous boolean
)
returns public.driver_app_feedback
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pending public.driver_feedback_obligations%rowtype;
  v_response public.driver_app_feedback%rowtype;
  v_name text;
begin
  select * into v_pending
    from public.driver_feedback_obligations
   where trip_id = p_trip_id
   for update;

  if not found or v_pending.driver_id <> auth.uid() then
    raise exception 'only the assigned driver may answer this app evaluation'
      using errcode = '42501';
  end if;

  if v_pending.response_id is not null then
    select * into v_response from public.driver_app_feedback
     where id = v_pending.response_id;
    return v_response;
  end if;

  if not coalesce(public.driver_feedback_answers_valid(p_answers), false) then
    raise exception 'all seven app-evaluation answers must use the 1-5 Likert scale'
      using errcode = '22023';
  end if;

  if p_comment is not null and char_length(p_comment) > 1000 then
    raise exception 'optional driver comments cannot exceed 1000 characters'
      using errcode = '22023';
  end if;

  if p_anonymous is null then
    raise exception 'the driver must explicitly choose the anonymity setting'
      using errcode = '22023';
  end if;

  if not p_anonymous then
    select display_name into v_name from public.profiles where id = auth.uid();
  end if;

  insert into public.driver_app_feedback (
    toda_zone_id, answers, comment, is_anonymous, driver_display_name
  )
  values (
    v_pending.toda_zone_id,
    p_answers,
    nullif(trim(coalesce(p_comment, '')), ''),
    p_anonymous,
    v_name
  )
  returning * into v_response;

  update public.driver_feedback_obligations
     set response_id = v_response.id, submitted_at = v_response.submitted_at
   where trip_id = p_trip_id;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (
    p_trip_id,
    auth.uid(),
    'evaluation.driver_feedback_submitted',
    jsonb_build_object('anonymous', p_anonymous)
  );

  return v_response;
end;
$$;

create or replace function public.admin_list_drivers()
returns table (
  driver_id uuid,
  display_name text,
  toda_zone_id uuid,
  toda_name text,
  body_number text,
  verification_status text,
  account_status text,
  is_online boolean,
  latitude double precision,
  longitude double precision,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles p
     where p.id = auth.uid() and p.role = 'admin' and p.status = 'active'
  ) then
    raise exception 'an active administrator account is required'
      using errcode = '42501';
  end if;

  return query
    select
      d.id,
      p.display_name,
      d.toda_zone_id,
      z.name,
      d.body_number,
      d.verification_status::text,
      p.status::text,
      coalesce(a.is_online, false),
      a.latitude,
      a.longitude,
      coalesce(a.updated_at, d.updated_at)
      from public.driver_profiles d
      join public.profiles p on p.id = d.id
      join public.toda_zones z on z.id = d.toda_zone_id
      left join public.driver_availability a on a.driver_id = d.id
     where public.has_admin_scope(auth.uid(), d.toda_zone_id)
     order by p.display_name;
end;
$$;

create or replace function public.admin_review_scoped_driver(
  p_driver_id uuid,
  p_decision text,
  p_reason text
)
returns public.driver_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.driver_profiles%rowtype;
  v_missing integer;
begin
  select * into v_driver from public.driver_profiles where id = p_driver_id for update;
  if not found or not public.has_admin_scope(auth.uid(), v_driver.toda_zone_id) then
    raise exception 'driver review is restricted to the assigned TODA or LGU'
      using errcode = '42501';
  end if;

  if p_decision not in ('approve', 'reject') then
    raise exception 'driver review decision must be approve or reject'
      using errcode = '22023';
  end if;

  if p_decision = 'reject' and not public.is_admin(auth.uid()) then
    raise exception 'TODA administrators may approve but cannot reject drivers'
      using errcode = '42501';
  end if;

  if public.is_admin(auth.uid()) then
    perform public.admin_review_driver(p_driver_id, p_decision, p_reason);
    select * into v_driver from public.driver_profiles where id = p_driver_id;
    return v_driver;
  end if;

  select count(*)::integer into v_missing
    from unnest(public.driver_required_document_types()) as required(document_type)
   where not exists (
     select 1 from public.driver_documents document
      where document.driver_id = p_driver_id
        and document.document_type = required.document_type
        and document.status = 'approved'
   );

  if v_missing > 0 then
    raise exception 'every required driver document must already be approved'
      using errcode = '22023';
  end if;

  update public.driver_profiles
     set verification_status = 'approved',
         rejection_reason = null,
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now()
   where id = p_driver_id
   returning * into v_driver;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason, metadata)
  values (
    auth.uid(),
    'driver.approve',
    p_driver_id,
    p_reason,
    jsonb_build_object('toda_zone_id', v_driver.toda_zone_id, 'scope', 'toda')
  );

  return v_driver;
end;
$$;

create or replace function public.get_feedback_summary(
  p_toda_zone_id uuid default null
)
returns table (
  toda_zone_id uuid,
  toda_name text,
  response_count bigint,
  unique_driver_count bigint,
  respondent_target integer,
  overall_mean numeric,
  question_means jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_settings public.app_evaluation_settings%rowtype;
begin
  if not exists (
    select 1 from public.profiles p
     where p.id = auth.uid() and p.role = 'admin' and p.status = 'active'
  ) then
    raise exception 'evaluation results are available only to active administrators'
      using errcode = '42501';
  end if;

  if p_toda_zone_id is not null
     and not public.has_admin_scope(auth.uid(), p_toda_zone_id) then
    raise exception 'evaluation results cannot cross TODA jurisdiction boundaries'
      using errcode = '42501';
  end if;

  select * into v_settings from public.app_evaluation_settings where id;

  return query
    select
      zone.id,
      zone.name,
      count(response.id),
      count(distinct obligation.driver_id),
      v_settings.respondent_target,
      round(
        avg(
          (
            (response.answers ->> 'ease_of_use')::numeric
            + (response.answers ->> 'booking_clarity')::numeric
            + (response.answers ->> 'navigation_clarity')::numeric
            + (response.answers ->> 'fare_fairness')::numeric
            + (response.answers ->> 'reliability')::numeric
            + (response.answers ->> 'safety_confidence')::numeric
            + (response.answers ->> 'continued_use')::numeric
          ) / 7
        ),
        2
      ),
      jsonb_build_object(
        'ease_of_use', round(avg((response.answers ->> 'ease_of_use')::numeric), 2),
        'booking_clarity', round(avg((response.answers ->> 'booking_clarity')::numeric), 2),
        'navigation_clarity', round(avg((response.answers ->> 'navigation_clarity')::numeric), 2),
        'fare_fairness', round(avg((response.answers ->> 'fare_fairness')::numeric), 2),
        'reliability', round(avg((response.answers ->> 'reliability')::numeric), 2),
        'safety_confidence', round(avg((response.answers ->> 'safety_confidence')::numeric), 2),
        'continued_use', round(avg((response.answers ->> 'continued_use')::numeric), 2)
      )
      from public.toda_zones zone
      left join public.driver_app_feedback response on response.toda_zone_id = zone.id
      left join public.driver_feedback_obligations obligation
        on obligation.response_id = response.id
     where zone.is_active
       and (p_toda_zone_id is null or zone.id = p_toda_zone_id)
       and public.has_admin_scope(auth.uid(), zone.id)
     group by zone.id, zone.name
     order by zone.name;
end;
$$;

create policy driver_documents_select_scoped_toda
  on public.driver_documents for select
  to authenticated
  using (
    exists (
      select 1 from public.driver_profiles d
       where d.id = driver_documents.driver_id
         and public.has_admin_scope((select auth.uid()), d.toda_zone_id)
    )
  );

-- PostgreSQL grants EXECUTE to PUBLIC by default. Every SECURITY DEFINER API
-- below explicitly removes that default before exposing only authenticated use.
revoke execute on function public.has_admin_scope(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.has_admin_scope(uuid, uuid)
  to authenticated, service_role;

revoke execute on function public.driver_feedback_answers_valid(jsonb)
  from public, anon, authenticated;
grant execute on function public.driver_feedback_answers_valid(jsonb)
  to authenticated, service_role;

revoke execute on function public.get_admin_scope()
  from public, anon, authenticated;
grant execute on function public.get_admin_scope()
  to authenticated, service_role;

revoke execute on function public.get_feedback_settings()
  from public, anon, authenticated;
grant execute on function public.get_feedback_settings()
  to authenticated, service_role;

revoke execute on function public.update_feedback_settings(integer, integer, boolean)
  from public, anon, authenticated;
grant execute on function public.update_feedback_settings(integer, integer, boolean)
  to authenticated, service_role;

revoke execute on function public.get_driver_feedback_state()
  from public, anon, authenticated;
grant execute on function public.get_driver_feedback_state()
  to authenticated, service_role;

revoke execute on function public.set_driver_availability(boolean, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.set_driver_availability(boolean, double precision, double precision)
  to authenticated, service_role;

revoke execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  from public, anon, authenticated;
grant execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  to authenticated, service_role;

revoke execute on function public.accept_ride(uuid)
  from public, anon, authenticated;
grant execute on function public.accept_ride(uuid)
  to authenticated, service_role;

revoke execute on function public.cancel_ride(uuid)
  from public, anon, authenticated;
grant execute on function public.cancel_ride(uuid)
  to authenticated, service_role;

revoke execute on function public.decline_ride(uuid)
  from public, anon, authenticated;
grant execute on function public.decline_ride(uuid)
  to authenticated, service_role;

revoke execute on function public.expire_ride(uuid)
  from public, anon, authenticated;
grant execute on function public.expire_ride(uuid)
  to authenticated, service_role;

revoke execute on function public.mark_arrived(uuid)
  from public, anon, authenticated;
grant execute on function public.mark_arrived(uuid)
  to authenticated, service_role;

revoke execute on function public.start_trip(uuid)
  from public, anon, authenticated;
grant execute on function public.start_trip(uuid)
  to authenticated, service_role;

revoke execute on function public.publish_driver_location(
  uuid, double precision, double precision, double precision
)
  from public, anon, authenticated;
grant execute on function public.publish_driver_location(
  uuid, double precision, double precision, double precision
)
  to authenticated, service_role;

revoke execute on function public.complete_trip(uuid)
  from public, anon, authenticated;
grant execute on function public.complete_trip(uuid)
  to authenticated, service_role;

revoke execute on function public.send_trip_message(uuid, text)
  from public, anon, authenticated;
grant execute on function public.send_trip_message(uuid, text)
  to authenticated, service_role;

revoke execute on function public.report_trip_chat(uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function public.report_trip_chat(uuid, text, boolean)
  to authenticated, service_role;

revoke execute on function public.create_sos_report(
  uuid, text, double precision, double precision, double precision, text
)
  from public, anon, authenticated;
grant execute on function public.create_sos_report(
  uuid, text, double precision, double precision, double precision, text
)
  to authenticated, service_role;

revoke execute on function public.update_sos_status(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.update_sos_status(uuid, text, text)
  to authenticated, service_role;

revoke execute on function public.submit_driver_feedback(uuid, jsonb, text, boolean)
  from public, anon, authenticated;
grant execute on function public.submit_driver_feedback(uuid, jsonb, text, boolean)
  to authenticated, service_role;

revoke execute on function public.admin_list_drivers()
  from public, anon, authenticated;
grant execute on function public.admin_list_drivers()
  to authenticated, service_role;

revoke execute on function public.admin_review_scoped_driver(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.admin_review_scoped_driver(uuid, text, text)
  to authenticated, service_role;

revoke execute on function public.get_feedback_summary(uuid)
  from public, anon, authenticated;
grant execute on function public.get_feedback_summary(uuid)
  to authenticated, service_role;

-- Supabase owns its realtime schema. PostgreSQL Changes only requires adding
-- public tables to its existing publication; the plain local pgTAP shim has none.
do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array[
      'trips',
      'driver_availability',
      'driver_profiles',
      'driver_documents',
      'trip_messages',
      'sos_reports',
      'driver_feedback_obligations',
      'driver_app_feedback',
      'app_evaluation_settings'
    ]
    loop
      if not exists (
        select 1
          from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = v_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table
        );
      end if;
    end loop;
  end if;
end;
$$;

-- An out-of-band hardening pass revoked PUBLIC from SECURITY DEFINER helpers.
-- Keep anonymous RLS checks non-throwing by applying admin policies only to the
-- authenticated role, instead of restoring public execution to is_admin().
alter policy profiles_select_admin
  on public.profiles to authenticated;
alter policy toda_zones_admin_write
  on public.toda_zones to authenticated;
alter policy fare_matrix_admin_write
  on public.fare_matrix to authenticated;
alter policy fare_discount_brackets_admin_write
  on public.fare_discount_brackets to authenticated;
alter policy driver_documents_admin_all
  on public.driver_documents to authenticated;
alter policy toda_members_select_admin
  on public.toda_members to authenticated;
alter policy driver_profiles_select_admin
  on public.driver_profiles to authenticated;
alter policy admin_audit_logs_select_admin
  on public.admin_audit_logs to authenticated;

-- PUBLIC inherits into authenticated/anon. These two identity-mutating helpers
-- must never become callable from an application client, regardless of any
-- broad security-definer grant made by an earlier migration.
revoke execute on function public.create_driver_record(
  uuid, uuid, uuid, text, text, text
)
  from public, anon, authenticated;

revoke execute on function public.admin_activate_new_driver(
  uuid, uuid, uuid, text, text
)
  from public, anon, authenticated;

grant execute on function public.admin_activate_new_driver(
  uuid, uuid, uuid, text, text
)
  to service_role;