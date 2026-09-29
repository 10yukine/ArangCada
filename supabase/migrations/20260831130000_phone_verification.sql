-- Phone (SMS OTP) verification of accounts.
--
-- Decided 31 August 2026. Registration collects name, email, mobile number and
-- password; the account is created, the user is signed in, and is then held on
-- a verify screen until a 6-digit SMS code proves they control the SIM.
--
-- WHY THE SIM AND NOT THE EMAIL
--
-- A Filipino commuter typically holds one or two SIMs but can create unlimited
-- email addresses. The SIM is the scarcer credential and therefore the better
-- anti-fraud anchor. This speaks directly to the "fake booking, then an unsafe
-- drop-off point" scenario Calamba City Hall raised in the same consultation:
-- a fake booking now costs the attacker a SIM rather than a throwaway inbox.
--
-- WHAT THIS IS NOT
--
-- This is contact-ownership verification. It is NOT liveness detection.
-- Liveness proves a live human is in front of a camera; OTP proves control of
-- a phone number. They are different mechanisms defeating different attacks.
-- Stage 2 (face capture + liveness, drivers only) is future work. Do not
-- describe this migration as liveness detection.

-- ---------------------------------------------------------------------------
-- The mirrored flag
-- ---------------------------------------------------------------------------
-- auth.users.phone_confirmed_at is the authority, but RLS policies and RPCs
-- cannot conveniently read the auth schema, and public.profiles is already the
-- denormalised identity table by existing precedent -- 20260825120000 did
-- exactly this for email. So the timestamp is mirrored, by trigger, never by
-- the client.

alter table public.profiles
  add column if not exists phone_verified_at timestamptz;

comment on column public.profiles.phone_verified_at is
  'Mirror of auth.users.phone_confirmed_at, maintained by trigger. Null means '
  'the account has not proved control of its mobile number. Never written by a '
  'client -- the only writer is sync_profile_phone_verified().';

create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set phone_verified_at = new.phone_confirmed_at
   where id = new.id
     and phone_verified_at is distinct from new.phone_confirmed_at;
  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors auth.users.phone_confirmed_at into profiles.phone_verified_at.';

drop trigger if exists on_auth_user_phone_confirmed on auth.users;
create trigger on_auth_user_phone_confirmed
  after insert or update of phone_confirmed_at on auth.users
  for each row execute function public.sync_profile_phone_verified();

-- Back-fill anything already confirmed. On a fresh project this is a no-op.
update public.profiles p
   set phone_verified_at = u.phone_confirmed_at
  from auth.users u
 where u.id = p.id
   and u.phone_confirmed_at is not null
   and p.phone_verified_at is null;

-- ---------------------------------------------------------------------------
-- The gate
-- ---------------------------------------------------------------------------

create or replace function public.is_verified_account(p_uid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.profiles p
     where p.id = p_uid
       and (
         p.phone_verified_at is not null
         -- DELIBERATE QA BYPASS, read this before changing it.
         --
         -- The hidden @arangcada.demo accounts cannot receive an SMS: they have
         -- no real SIM behind them. Without an exemption every automated test
         -- and every device-QA session would have to round-trip a live text
         -- message, which is neither free nor reliable.
         --
         -- is_internal_tester is NOT self-service. profiles has a privilege
         -- guard (20260825120100) that stops a user setting their own
         -- privileged columns, so an ordinary account cannot grant itself this
         -- flag. 69_phone_verification_test.sql asserts a non-tester gets no
         -- benefit from this branch.
         --
         -- It must be removed or re-audited before the pilot beta
         or p.is_internal_tester
       )
  );
$$;

comment on function public.is_verified_account(uuid) is
  'True when the account has proved control of its mobile number via SMS OTP, '
  'or is an explicitly flagged internal tester. The single verification gate; '
  'request_ride, can_driver_go_online and create_ride_share_link all consult it.';

revoke execute on function public.is_verified_account(uuid) from public, anon;
grant execute on function public.is_verified_account(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Enforcement, server-side
-- ---------------------------------------------------------------------------
-- Hiding the dashboard in Flutter is a convenience, not a
-- control. A tampered client that skips the verify screen must gain nothing.

-- 1. A driver with an unverified number cannot go online, and therefore cannot
--    be dispatched -- the candidate query in request_ride already filters on
--    can_driver_go_online(). The predicate is inlined rather than calling
--    is_verified_account() because this function already joins profiles, and
--    an inlined condition is visible to anyone reading the go-online gate.
create or replace function public.can_driver_go_online(
  p_uid uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.driver_profiles d
      join public.profiles p on p.id = d.id
     where d.id = p_uid
       and d.verification_status = 'approved'
       and p.role   = 'driver'
       and p.status = 'active'
       and (d.license_expires_on is null or d.license_expires_on >= current_date)
       and (p.phone_verified_at is not null or p.is_internal_tester)
  );
$$;

comment on function public.can_driver_go_online(uuid) is
  'True when the driver is approved, still role=driver, not suspended, holds a '
  'licence that has not lapsed, and has verified their mobile number by SMS '
  'OTP (or is a flagged internal tester). The single go-online gate.';

revoke execute on function public.can_driver_go_online(uuid) from anon;

-- 2. An unverified commuter cannot book.
--
-- Only the guard is new; the rest of this function body is carried over
-- verbatim from 20260831100000_staged_dispatch_radius.sql.
create or replace function public.request_ride(p_pickup_lat double precision, p_pickup_lng double precision, p_destination_lat double precision, p_destination_lng double precision, p_pickup_label text, p_destination_label text, p_idempotency_key text)
 returns public.trips
 language plpgsql
 security definer
 set search_path to ''
as $function$
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
  v_radius_m integer;
begin
  select * into v_rider
    from public.profiles
   where id = auth.uid()
   for update;

  if not found or v_rider.role <> 'commuter' or v_rider.status <> 'active' then
    raise exception 'an active commuter account is required to request a ride'
      using errcode = '42501';
  end if;

  -- NEW: verification gate.
  if v_rider.phone_verified_at is null and not v_rider.is_internal_tester then
    raise exception 'verify your mobile number before booking a ride'
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
    raise exception 'pickup is outside the Calamba service area'
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

  v_radius_m := public.dispatch_radius_m(null);

  select availability.driver_id, driver_profile.display_name
    into v_driver_id, v_driver_name
    from public.driver_availability availability
    join public.driver_profiles driver on driver.id = availability.driver_id
    join public.profiles driver_profile on driver_profile.id = driver.id
   where availability.is_online
     and public.can_driver_go_online(driver.id)
     and driver_profile.is_internal_tester = v_zone.is_internal_test
     and availability.latitude is not null
     and availability.longitude is not null
     and public.st_distancesphere(
           v_pickup,
           public.st_setsrid(
             public.st_makepoint(availability.longitude, availability.latitude), 4326)
         ) <= v_radius_m
     and not exists (
       select 1 from public.driver_feedback_obligations pending
        where pending.driver_id = driver.id and pending.submitted_at is null
     )
   order by
     public.st_distancesphere(
       v_pickup,
       public.st_setsrid(
         public.st_makepoint(availability.longitude, availability.latitude), 4326)
     ),
     availability.updated_at desc
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
    jsonb_build_object('assigned', v_driver_id is not null, 'radius_m', v_radius_m)
  );

  return v_trip;
end;
$function$;

revoke execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  from public, anon;
grant execute on function public.request_ride(
  double precision, double precision, double precision, double precision,
  text, text, text
)
  to authenticated, service_role;

-- 3. An unverified commuter cannot mint a public tracking link. Handing an
--    unverified account the system's only anon-readable surface would be a poor
--    trade.
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
  if not public.is_verified_account(auth.uid()) then
    raise exception 'verify your mobile number before sharing a ride link'
      using errcode = '42501';
  end if;

  select * into v_trip
    from public.trips
   where id = p_trip_id;

  if not found or v_trip.rider_id <> auth.uid() then
    raise exception 'that trip does not belong to you'
      using errcode = '42501';
  end if;

  if v_trip.status in ('completed', 'cancelled_by_rider', 'cancelled_by_driver',
                       'no_driver_available') then
    raise exception 'this trip has already ended'
      using errcode = '22023';
  end if;

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

revoke execute on function public.create_ride_share_link(uuid) from public, anon;
grant execute on function public.create_ride_share_link(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Resend throttle
-- ---------------------------------------------------------------------------
-- Every SMS costs money and an unthrottled send endpoint is an SMS-pumping
-- target: an attacker loops the resend call and drains the prepaid balance.
-- Supabase applies its own rate limits, but they are per-project rather than
-- per-number, so this records attempts we can reason about and test.

create table if not exists public.otp_send_log (
  id         bigserial primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  phone_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists otp_send_log_user_time_idx
  on public.otp_send_log (user_id, created_at desc);

comment on table public.otp_send_log is
  'One row per OTP send attempt, for throttling. Stores a HASH of the number, '
  'never the number itself -- project policy forbids logging phone numbers.';

alter table public.otp_send_log enable row level security;

create policy otp_send_log_select_own
  on public.otp_send_log for select
  to authenticated
  using (user_id = (select auth.uid()));

-- No insert/update/delete policy: only the security-definer function below
-- writes here.

create or replace function public.record_otp_send(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_recent integer;
  v_hourly integer;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select count(*) into v_recent
    from public.otp_send_log
   where user_id = v_uid and created_at > now() - interval '60 seconds';

  if v_recent > 0 then
    raise exception 'please wait a minute before requesting another code'
      using errcode = '22023';
  end if;

  select count(*) into v_hourly
    from public.otp_send_log
   where user_id = v_uid and created_at > now() - interval '1 hour';

  if v_hourly >= 5 then
    raise exception 'too many code requests, try again later'
      using errcode = '22023';
  end if;

  insert into public.otp_send_log (user_id, phone_hash)
  values (v_uid, encode(sha256(coalesce(p_phone, '')::bytea), 'hex'));

  return true;
end;
$$;

comment on function public.record_otp_send(text) is
  'Throttles OTP sends: at most one per 60 seconds and five per hour per '
  'account. Raises rather than returning false so a client cannot ignore it. '
  'Hashes the number -- rule 10 forbids storing it.';

revoke execute on function public.record_otp_send(text) from public, anon;
grant execute on function public.record_otp_send(text) to authenticated, service_role;
