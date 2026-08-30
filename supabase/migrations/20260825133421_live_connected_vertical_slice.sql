-- First connected commuter/driver/admin slice. Cabuyao is explicitly limited
-- to trusted developer-test identities; Calamba remains the real service area.

alter table public.profiles
  add column is_internal_tester boolean not null default false;

comment on column public.profiles.is_internal_tester is
  'Privileged, developer-only access to synthetic internal-test jurisdictions.';

create or replace function public.guard_profiles_privileged_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user = 'authenticated'
     and (new.role is distinct from old.role
          or new.status is distinct from old.status
          or new.is_internal_tester is distinct from old.is_internal_tester) then
    raise exception 'profiles.role and profiles.status can only change through a security definer RPC, never a direct update'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

alter table public.toda_zones
  add column is_internal_test boolean not null default false;

comment on column public.toda_zones.is_internal_test is
  'Synthetic developer-only geography, never an official LGU/TODA boundary.';

insert into public.toda_zones (
  code, name, barangay, boundary, terminal_point, is_internal_test
)
values (
  'DEV-SJVTODA-CABUYAO',
  'SJVTODA - Cabuyao developer test (provisional)',
  'Cabuyao - INTERNAL DEVELOPMENT TEST ONLY',
  public.st_geomfromtext(
    'POLYGON((121.055 14.235,121.175 14.235,121.175 14.330,121.055 14.330,121.055 14.235))',
    4326
  ),
  public.st_setsrid(public.st_makepoint(121.115, 14.2825), 4326),
  true
);

create table public.admin_scopes (
  admin_id uuid primary key references public.profiles (id) on delete cascade,
  scope text not null check (scope in ('lgu', 'toda')),
  toda_zone_id uuid references public.toda_zones (id),
  created_at timestamptz not null default now(),
  constraint admin_scopes_zone_matches_scope check (
    (scope = 'lgu' and toda_zone_id is null)
    or (scope = 'toda' and toda_zone_id is not null)
  )
);

create index admin_scopes_zone_idx on public.admin_scopes (toda_zone_id);

-- Legacy onboarding/tests treat an unscoped role=admin account as LGU. A TODA
-- assignment explicitly removes that account from every existing global policy.
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = uid
       and p.role = 'admin'
       and p.status = 'active'
       and not exists (
         select 1
           from public.admin_scopes s
          where s.admin_id = p.id
            and s.scope = 'toda'
       )
  );
$$;

create or replace function public.has_admin_scope(
  p_admin_id uuid,
  p_toda_zone_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_admin(p_admin_id)
      or exists (
           select 1
             from public.admin_scopes s
             join public.profiles p on p.id = s.admin_id
            where s.admin_id = p_admin_id
              and s.scope = 'toda'
              and s.toda_zone_id = p_toda_zone_id
              and p.role = 'admin'
              and p.status = 'active'
         );
$$;

alter table public.admin_scopes enable row level security;

create policy admin_scopes_select_self_or_lgu
  on public.admin_scopes for select
  to authenticated
  using (admin_id = (select auth.uid()) or public.is_admin((select auth.uid())));

alter policy toda_zones_select_authenticated on public.toda_zones
  using (
    is_active
    and (
      not is_internal_test
      or exists (
        select 1
          from public.profiles p
         where p.id = (select auth.uid())
           and p.is_internal_tester
      )
      or public.has_admin_scope((select auth.uid()), id)
    )
  );

alter table public.trips
  add column pickup_lat double precision
    generated always as (public.st_y(pickup)) stored,
  add column pickup_lng double precision
    generated always as (public.st_x(pickup)) stored,
  add column destination_lat double precision
    generated always as (public.st_y(dropoff)) stored,
  add column destination_lng double precision
    generated always as (public.st_x(dropoff)) stored,
  add column pickup_label text not null default '',
  add column destination_label text not null default '',
  add column rider_display_name text not null default '',
  add column driver_display_name text,
  add column toda_name text not null default '',
  add column payment_method text not null default 'cash',
  add column accept_by timestamptz,
  add column accepted_at timestamptz,
  add column arrived_at timestamptz,
  add column started_at timestamptz,
  add column completion_available_at timestamptz,
  add column cancellation_reason text,
  add constraint trips_cash_only check (payment_method = 'cash'),
  add constraint trips_pickup_label_length check (char_length(pickup_label) <= 160),
  add constraint trips_destination_label_length check (char_length(destination_label) <= 160);

create unique index trips_one_active_per_driver
  on public.trips (driver_id)
  where driver_id is not null
    and status in (
      'requested', 'searching_driver', 'driver_assigned', 'accepted',
      'driver_en_route', 'arrived', 'in_progress', 'emergency_reported'
    );

drop policy trips_admin_all on public.trips;

create policy trips_select_scoped_admin
  on public.trips for select
  to authenticated
  using (public.has_admin_scope((select auth.uid()), toda_zone_id));

create policy driver_profiles_select_scoped_toda
  on public.driver_profiles for select
  to authenticated
  using (public.has_admin_scope((select auth.uid()), toda_zone_id));

create table public.driver_availability (
  driver_id uuid primary key references public.driver_profiles (id) on delete cascade,
  toda_zone_id uuid not null references public.toda_zones (id),
  is_online boolean not null default false,
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  updated_at timestamptz not null default now(),
  constraint driver_availability_coordinates check (
    (latitude is null and longitude is null)
    or (latitude between -90 and 90 and longitude between -180 and 180)
  ),
  constraint driver_availability_accuracy check (
    accuracy_meters is null or accuracy_meters >= 0
  )
);

create index driver_availability_zone_online_idx
  on public.driver_availability (toda_zone_id, is_online, updated_at desc);

create table public.trip_events (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id),
  actor_id uuid references public.profiles (id),
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint trip_events_metadata_no_sensitive_fields check (
    not (
      metadata ? 'phone' or metadata ? 'email' or metadata ? 'display_name'
      or metadata ? 'latitude' or metadata ? 'longitude' or metadata ? 'body'
    )
  )
);

create index trip_events_trip_time_idx on public.trip_events (trip_id, created_at);

create table public.trip_messages (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id),
  sender_id uuid not null references public.profiles (id),
  body text not null,
  created_at timestamptz not null default now(),
  constraint trip_messages_body_length check (
    char_length(trim(body)) between 1 and 1000
  )
);

create index trip_messages_trip_time_idx on public.trip_messages (trip_id, created_at);

create table public.sos_reports (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id),
  toda_zone_id uuid not null references public.toda_zones (id),
  reporter_id uuid not null references public.profiles (id),
  reporter_role text not null check (reporter_role in ('commuter', 'driver')),
  reporter_display_name text not null,
  driver_display_name text,
  toda_name text not null,
  reason text not null check (char_length(trim(reason)) between 1 and 300),
  status text not null default 'new'
    check (status in ('new', 'acknowledged', 'investigating', 'escalated', 'resolved', 'dismissed')),
  priority text not null default 'critical'
    check (priority in ('normal', 'high', 'critical')),
  latitude double precision,
  longitude double precision,
  accuracy_meters double precision,
  idempotency_key text not null unique,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sos_reports_coordinates check (
    (latitude is null and longitude is null)
    or (latitude between -90 and 90 and longitude between -180 and 180)
  ),
  constraint sos_reports_accuracy check (accuracy_meters is null or accuracy_meters >= 0),
  constraint sos_reports_note_length check (admin_note is null or char_length(admin_note) <= 1000)
);

create index sos_reports_zone_created_idx on public.sos_reports (toda_zone_id, created_at desc);
create index sos_reports_status_created_idx on public.sos_reports (status, created_at desc);

create table public.reported_trip_chats (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id),
  reporter_id uuid not null references public.profiles (id),
  reason text not null check (char_length(trim(reason)) between 1 and 500),
  consented_at timestamptz not null default now(),
  messages jsonb not null,
  created_at timestamptz not null default now()
);

create index reported_trip_chats_trip_idx on public.reported_trip_chats (trip_id);

create table public.app_evaluation_settings (
  id boolean primary key default true check (id),
  feedback_interval integer not null default 1 check (feedback_interval between 1 and 1000),
  repeat_feedback boolean not null default true,
  respondent_target integer not null default 10 check (respondent_target between 1 and 10000),
  updated_by uuid references public.profiles (id),
  updated_at timestamptz not null default now()
);

insert into public.app_evaluation_settings (id) values (true);

create or replace function public.driver_feedback_answers_valid(p_answers jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(p_answers) = 'object'
     and (select count(*) from jsonb_object_keys(p_answers)) = 7
     and not exists (
       select 1
         from unnest(array[
           'ease_of_use', 'booking_clarity', 'navigation_clarity',
           'fare_fairness', 'reliability', 'safety_confidence', 'continued_use'
         ]) as expected(answer_key)
        where not (p_answers ? expected.answer_key)
           or jsonb_typeof(p_answers -> expected.answer_key) <> 'number'
           or (p_answers ->> expected.answer_key) !~ '^[1-5]$'
     );
$$;

create table public.driver_app_feedback (
  id uuid primary key default gen_random_uuid(),
  toda_zone_id uuid not null references public.toda_zones (id),
  answers jsonb not null,
  comment text,
  is_anonymous boolean not null default true,
  driver_display_name text,
  submitted_at timestamptz not null default now(),
  constraint driver_app_feedback_answers check (public.driver_feedback_answers_valid(answers)),
  constraint driver_app_feedback_comment_length check (
    comment is null or char_length(comment) <= 1000
  ),
  constraint driver_app_feedback_anonymity check (
    (is_anonymous and driver_display_name is null)
    or (not is_anonymous and driver_display_name is not null)
  )
);

create index driver_app_feedback_zone_time_idx
  on public.driver_app_feedback (toda_zone_id, submitted_at desc);

create table public.driver_feedback_obligations (
  trip_id uuid primary key references public.trips (id),
  driver_id uuid not null references public.driver_profiles (id),
  toda_zone_id uuid not null references public.toda_zones (id),
  response_id uuid unique references public.driver_app_feedback (id),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  constraint driver_feedback_obligations_submission check (
    (response_id is null and submitted_at is null)
    or (response_id is not null and submitted_at is not null)
  )
);

create unique index driver_feedback_one_pending_idx
  on public.driver_feedback_obligations (driver_id)
  where submitted_at is null;

alter table public.driver_availability enable row level security;
alter table public.trip_events enable row level security;
alter table public.trip_messages enable row level security;
alter table public.sos_reports enable row level security;
alter table public.reported_trip_chats enable row level security;
alter table public.app_evaluation_settings enable row level security;
alter table public.driver_app_feedback enable row level security;
alter table public.driver_feedback_obligations enable row level security;

create policy driver_availability_select_authorized
  on public.driver_availability for select
  to authenticated
  using (
    driver_id = (select auth.uid())
    or public.has_admin_scope((select auth.uid()), toda_zone_id)
    or exists (
      select 1
        from public.trips t
       where t.driver_id = driver_availability.driver_id
         and t.rider_id = (select auth.uid())
         and t.status in (
           'driver_assigned', 'accepted', 'driver_en_route',
           'arrived', 'in_progress', 'emergency_reported'
         )
    )
  );

create policy trip_events_select_scoped_admin
  on public.trip_events for select
  to authenticated
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_events.trip_id
         and public.has_admin_scope((select auth.uid()), t.toda_zone_id)
    )
  );

create policy trip_messages_select_participant
  on public.trip_messages for select
  to authenticated
  using (
    exists (
      select 1 from public.trips t
       where t.id = trip_messages.trip_id
         and ((select auth.uid()) = t.rider_id or (select auth.uid()) = t.driver_id)
         and (t.completed_at is null or t.completed_at >= now() - interval '30 days')
    )
  );

create policy sos_reports_select_reporter_or_scoped_admin
  on public.sos_reports for select
  to authenticated
  using (
    reporter_id = (select auth.uid())
    or public.has_admin_scope((select auth.uid()), toda_zone_id)
  );

create policy reported_trip_chats_select_reporter_or_lgu
  on public.reported_trip_chats for select
  to authenticated
  using (reporter_id = (select auth.uid()) or public.is_admin((select auth.uid())));

create policy app_evaluation_settings_select_authenticated
  on public.app_evaluation_settings for select
  to authenticated
  using (true);

create policy driver_app_feedback_select_scoped_admin
  on public.driver_app_feedback for select
  to authenticated
  using (public.has_admin_scope((select auth.uid()), toda_zone_id));

create policy driver_feedback_obligations_select_driver
  on public.driver_feedback_obligations for select
  to authenticated
  using (driver_id = (select auth.uid()));

-- Hosted projects no longer guarantee automatic Data API grants for new tables.
revoke all on
  public.admin_scopes,
  public.driver_availability,
  public.trip_events,
  public.trip_messages,
  public.sos_reports,
  public.reported_trip_chats,
  public.app_evaluation_settings,
  public.driver_app_feedback,
  public.driver_feedback_obligations
from anon, authenticated;

grant select on
  public.admin_scopes,
  public.driver_availability,
  public.trip_events,
  public.trip_messages,
  public.sos_reports,
  public.reported_trip_chats,
  public.app_evaluation_settings,
  public.driver_app_feedback,
  public.driver_feedback_obligations,
  public.profiles,
  public.toda_zones,
  public.driver_profiles,
  public.trips,
  public.fare_matrix,
  public.fare_discount_brackets
to authenticated;

-- Booking must pass trusted fare/geofence/dispatch checks; direct writes cannot.
revoke insert on public.trips from authenticated;

create or replace function public.get_admin_scope()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile public.profiles%rowtype;
  v_scope public.admin_scopes%rowtype;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if not found or v_profile.role <> 'admin' or v_profile.status <> 'active' then
    raise exception 'an active administrator account is required'
      using errcode = '42501';
  end if;

  select * into v_scope from public.admin_scopes where admin_id = v_profile.id;

  return jsonb_build_object(
    'admin_role', coalesce(v_scope.scope, 'lgu'),
    'toda_zone_id', v_scope.toda_zone_id,
    'display_name', v_profile.display_name
  );
end;
$$;

create or replace function public.get_feedback_settings()
returns public.app_evaluation_settings
language sql
stable
security definer
set search_path = ''
as $$
  select s.*
    from public.app_evaluation_settings s
   where s.id
     and auth.uid() is not null;
$$;

create or replace function public.update_feedback_settings(
  p_feedback_interval integer,
  p_respondent_target integer,
  p_repeat_feedback boolean
)
returns public.app_evaluation_settings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.app_evaluation_settings%rowtype;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an LGU administrator can change evaluation settings'
      using errcode = '42501';
  end if;

  update public.app_evaluation_settings
     set feedback_interval = p_feedback_interval,
         respondent_target = p_respondent_target,
         repeat_feedback = p_repeat_feedback,
         updated_by = auth.uid(),
         updated_at = now()
   where id
   returning * into v_settings;

  insert into public.admin_audit_logs (actor_id, action, metadata)
  values (
    auth.uid(),
    'evaluation.settings.update',
    jsonb_build_object(
      'feedback_interval', p_feedback_interval,
      'respondent_target', p_respondent_target,
      'repeat_feedback', p_repeat_feedback
    )
  );

  return v_settings;
end;
$$;

create or replace function public.get_driver_feedback_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_driver uuid := auth.uid();
  v_trip uuid;
  v_completed integer;
  v_settings public.app_evaluation_settings%rowtype;
begin
  if v_driver is null or not exists (
    select 1 from public.driver_profiles where id = v_driver
  ) then
    raise exception 'an authenticated driver account is required'
      using errcode = '42501';
  end if;

  select * into v_settings from public.app_evaluation_settings where id;

  select trip_id into v_trip
    from public.driver_feedback_obligations
   where driver_id = v_driver and submitted_at is null;

  select count(*)::integer into v_completed
    from public.trips
   where driver_id = v_driver and status = 'completed';

  return jsonb_build_object(
    'feedback_interval', v_settings.feedback_interval,
    'repeat_feedback', v_settings.repeat_feedback,
    'pending', v_trip is not null,
    'pending_trip_id', v_trip,
    'completed_trips', v_completed
  );
end;
$$;

create or replace function public.set_driver_availability(
  p_online boolean,
  p_lat double precision,
  p_lng double precision
)
returns public.driver_availability
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.driver_profiles%rowtype;
  v_profile public.profiles%rowtype;
  v_zone public.toda_zones%rowtype;
  v_result public.driver_availability%rowtype;
begin
  select * into v_driver from public.driver_profiles where id = auth.uid();
  if not found then
    raise exception 'an authenticated driver account is required'
      using errcode = '42501';
  end if;

  select * into v_profile from public.profiles where id = v_driver.id;
  select * into v_zone from public.toda_zones where id = v_driver.toda_zone_id;

  if p_online then
    if not public.can_driver_go_online(v_driver.id) then
      raise exception 'only approved active drivers can receive bookings'
        using errcode = '42501';
    end if;

    if exists (
      select 1 from public.driver_feedback_obligations
       where driver_id = v_driver.id and submitted_at is null
    ) then
      raise exception 'mandatory driver app feedback must be submitted first'
        using errcode = '42501';
    end if;

    if exists (
      select 1 from public.trips t
       where t.driver_id = v_driver.id
         and t.status in (
           'requested', 'searching_driver', 'driver_assigned', 'accepted',
           'driver_en_route', 'arrived', 'in_progress', 'emergency_reported'
         )
    ) then
      raise exception 'a driver cannot receive a second active trip'
        using errcode = '22023';
    end if;

    if v_zone.is_internal_test and not v_profile.is_internal_tester then
      raise exception 'the Cabuyao exception is restricted to developer-test identities'
        using errcode = '42501';
    end if;

    if p_lat is null or p_lng is null
       or not public.is_point_in_toda_zone(v_driver.toda_zone_id, p_lng, p_lat) then
      raise exception 'an online driver must be located inside the assigned TODA'
        using errcode = '22023';
    end if;
  end if;

  insert into public.driver_availability (
    driver_id, toda_zone_id, is_online, latitude, longitude, updated_at
  )
  values (v_driver.id, v_driver.toda_zone_id, p_online, p_lat, p_lng, now())
  on conflict (driver_id) do update
     set toda_zone_id = excluded.toda_zone_id,
         is_online = excluded.is_online,
         latitude = excluded.latitude,
         longitude = excluded.longitude,
         updated_at = now()
  returning * into v_result;

  return v_result;
end;
$$;

create or replace function public.request_ride(
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_destination_lat double precision,
  p_destination_lng double precision,
  p_pickup_label text,
  p_destination_label text,
  p_idempotency_key text
)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rider public.profiles%rowtype;
  v_zone public.toda_zones%rowtype;
  v_destination_zone public.toda_zones%rowtype;
  v_trip public.trips%rowtype;
  v_driver_id uuid;
  v_driver_name text;
  v_pickup public.geometry;
  v_dropoff public.geometry;
  v_distance integer;
begin
  select * into v_rider
    from public.profiles
   where id = auth.uid()
   for update;

  if not found or v_rider.role <> 'commuter' or v_rider.status <> 'active' then
    raise exception 'an active commuter account is required to request a ride'
      using errcode = '42501';
  end if;

  if nullif(trim(coalesce(p_idempotency_key, '')), '') is null
     or char_length(p_idempotency_key) > 128 then
    raise exception 'a booking idempotency key is required'
      using errcode = '22023';
  end if;

  select * into v_trip
    from public.trips
   where idempotency_key = p_idempotency_key;

  if found then
    if v_trip.rider_id <> v_rider.id then
      raise exception 'that booking key belongs to another commuter'
        using errcode = '42501';
    end if;
    return v_trip;
  end if;

  if p_pickup_lat is null or p_pickup_lng is null
     or p_destination_lat is null or p_destination_lng is null
     or p_pickup_lat not between -90 and 90
     or p_destination_lat not between -90 and 90
     or p_pickup_lng not between -180 and 180
     or p_destination_lng not between -180 and 180 then
    raise exception 'valid pickup and destination coordinates are required'
      using errcode = '22023';
  end if;

  select z.* into v_zone
    from public.toda_zone_covering(p_pickup_lng, p_pickup_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found then
    raise exception 'pickup is outside all approved or developer-test TODA jurisdictions'
      using errcode = '22023';
  end if;

  if v_zone.is_internal_test and not v_rider.is_internal_tester then
    raise exception 'the Cabuyao exception is restricted to developer-test identities'
      using errcode = '42501';
  end if;

  select z.* into v_destination_zone
    from public.toda_zone_covering(p_destination_lng, p_destination_lat) matched
    join public.toda_zones z on z.id = matched.zone_id;

  if not found or (v_destination_zone.is_internal_test and not v_rider.is_internal_tester) then
    raise exception 'destination is outside the Calamba/internal-test service area'
      using errcode = '22023';
  end if;

  v_pickup := public.st_setsrid(public.st_makepoint(p_pickup_lng, p_pickup_lat), 4326);
  v_dropoff := public.st_setsrid(public.st_makepoint(p_destination_lng, p_destination_lat), 4326);
  v_distance := round(public.st_distancesphere(v_pickup, v_dropoff))::integer;

  select availability.driver_id, driver_profile.display_name
    into v_driver_id, v_driver_name
    from public.driver_availability availability
    join public.driver_profiles driver on driver.id = availability.driver_id
    join public.profiles driver_profile on driver_profile.id = driver.id
   where availability.toda_zone_id = v_zone.id
     and availability.is_online
     and public.can_driver_go_online(driver.id)
     and (not v_zone.is_internal_test or driver_profile.is_internal_tester)
     and not exists (
       select 1 from public.driver_feedback_obligations pending
        where pending.driver_id = driver.id and pending.submitted_at is null
     )
   order by availability.updated_at desc
   for update of availability skip locked
   limit 1;

  if v_driver_id is not null then
    update public.driver_availability
       set is_online = false, updated_at = now()
     where driver_id = v_driver_id;
  end if;

  insert into public.trips (
    rider_id, driver_id, toda_zone_id, ride_type, status, pickup, dropoff,
    distance_m, fare_estimate, idempotency_key, pickup_label,
    destination_label, rider_display_name, driver_display_name, toda_name,
    payment_method, accept_by
  )
  values (
    v_rider.id,
    v_driver_id,
    v_zone.id,
    'special',
    case when v_driver_id is null
         then 'searching_driver'::public.trip_status
         else 'driver_assigned'::public.trip_status end,
    v_pickup,
    v_dropoff,
    v_distance,
    public.compute_fare(v_distance, 'special', 'standard', 1),
    p_idempotency_key,
    coalesce(trim(p_pickup_label), ''),
    coalesce(trim(p_destination_label), ''),
    v_rider.display_name,
    v_driver_name,
    v_zone.name,
    'cash',
    case when v_driver_id is not null then now() + interval '30 seconds' end
  )
  returning * into v_trip;

  insert into public.trip_events (trip_id, actor_id, event_type, metadata)
  values (
    v_trip.id,
    v_rider.id,
    'ride.requested',
    jsonb_build_object('assigned', v_driver_id is not null)
  );

  return v_trip;
end;
$$;

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

  if not found or v_trip.driver_id <> auth.uid() then
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

create or replace function public.cancel_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
  v_status public.trip_status;
begin
  select * into v_trip from public.trips where id = p_trip_id for update;

  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
    raise exception 'only a trip participant can cancel this ride'
      using errcode = '42501';
  end if;

  v_status := case
    when auth.uid() = v_trip.driver_id then 'cancelled_by_driver'::public.trip_status
    else 'cancelled_by_rider'::public.trip_status
  end;

  if v_trip.status = v_status then
    return v_trip;
  end if;

  if v_trip.status in ('completed', 'cancelled_by_rider', 'cancelled_by_driver', 'no_driver_available') then
    raise exception 'a closed trip cannot be cancelled again'
      using errcode = '22023';
  end if;

  update public.trips
     set status = v_status, cancellation_reason = v_status::text, updated_at = now()
   where id = p_trip_id
   returning * into v_trip;

  if v_trip.driver_id is not null then
    update public.driver_availability
       set is_online = public.can_driver_go_online(v_trip.driver_id), updated_at = now()
     where driver_id = v_trip.driver_id;
  end if;

  insert into public.trip_events (trip_id, actor_id, event_type)
  values (p_trip_id, auth.uid(), 'ride.' || v_status::text);

  return v_trip;
end;
$$;

create or replace function public.decline_ride(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip public.trips%rowtype;
begin
  select * into v_trip from public.trips where id = p_trip_id;
  if not found or v_trip.driver_id <> auth.uid() then
    raise exception 'only the offered driver can decline this ride'
      using errcode = '42501';
  end if;
  if v_trip.status = 'cancelled_by_driver' then
    return v_trip;
  end if;
  if v_trip.status <> 'driver_assigned' then
    raise exception 'only an unanswered ride offer can be declined'
      using errcode = '22023';
  end if;
  return public.cancel_ride(p_trip_id);
end;
$$;

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
  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
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
  if not found or v_trip.driver_id <> auth.uid() then
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
  if not found or v_trip.driver_id <> auth.uid() then
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

  if not found or v_trip.driver_id <> auth.uid() then
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

  if not found or (auth.uid() <> v_trip.rider_id and auth.uid() <> v_trip.driver_id) then
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
