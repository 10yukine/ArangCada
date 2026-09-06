-- Discount eligibility: ID photo capture, admin review, and the fare it
-- actually changes once approved.
--
-- WHY THIS EXISTS
--
-- discount_eligibility_screen.dart already said, in its own doc comment:
-- "The intended production check is server-side... None of that exists yet.
-- Nothing on this screen may claim an ID was read, matched, or approved by
-- a machine -- submitting only records the commuter's intent to claim."
-- This migration is that server-side half -- manual admin review, not OCR
-- (OCR/automatic ID reading is still explicitly future work, unchanged).
-- See .pipeline/specs.md Spec 14.
--
-- Owner decision, 5 Sep 2026: the discount stays OFF until an admin
-- approves it (mirrors driver_profiles.verification_status's
-- unverified -> pending_review -> approved/rejected shape), and once
-- approved it must actually reduce the fare on the next booking, not just
-- flip a flag nothing reads -- see the request_ride() redefinition at the
-- bottom of this file.

-- ---------------------------------------------------------------------------
-- Storage: the first bucket in this repo.
-- ---------------------------------------------------------------------------
-- Signed-URL, not public-read (owner decision, 5 Sep 2026 -- named
-- individuals in one city; see Spec 11 §4's original flag, and Spec 15,
-- which reuses this exact bucket-policy shape for profile photos). A user
-- may write and read only under their own auth.uid()-prefixed path; an
-- admin may also read (to review a claim), but through the same RLS-gated
-- `createSignedUrl` call the client already uses for its own photo -- no
-- separate "mint a URL for an arbitrary path" function exists, because
-- Storage's own row-level security on `storage.objects` already decides who
-- may read which object, and a signed URL request is just a read.
insert into storage.buckets (id, name, public)
values ('discount-eligibility-ids', 'discount-eligibility-ids', false)
on conflict (id) do nothing;

-- Deliberately NOT `alter table storage.objects enable row level security`
-- here. It reads as harmless (RLS is already on by default on hosted
-- Supabase), but a migration actually failed on the real project, 6 Sep
-- 2026: `must be owner of table objects` -- storage.objects is owned by
-- supabase_storage_admin there, not the role migrations run as, and
-- Postgres still requires ownership to attempt the ALTER even when the
-- target state already holds. The local-only equivalent lives in
-- supabase/tests/00_bootstrap_local.sql, where the stub table is owned by
-- the same role that creates it.

create policy discount_id_insert_own
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'discount-eligibility-ids'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy discount_id_select_own_or_admin
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'discount-eligibility-ids'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.is_admin((select auth.uid()))
    )
  );

-- No update/delete policy -- a submitted ID photo is immutable; a mistaken
-- claim is rejected by an admin and the commuter submits a fresh one (a
-- fresh path, since submit_fare_class_claim() below refuses a second
-- pending claim, not a second claim after a decision).

-- ---------------------------------------------------------------------------
-- profiles.fare_class -- the column request_ride() actually bills against
-- ---------------------------------------------------------------------------
-- Reuses passenger_fare_class ('standard' | 'discounted',
-- 20260729000000_lgu_fare_matrix_ordinance_743.sql) directly rather than
-- inventing a parallel type -- it is already exactly the type
-- compute_fare()'s p_fare_class parameter expects, so no translation layer
-- sits between "an admin approved this" and "the booking is billed less".
alter table public.profiles
  add column if not exists fare_class public.passenger_fare_class not null default 'standard';

comment on column public.profiles.fare_class is
  'Billing class passed to compute_fare() by request_ride(). Never writable '
  'by the client -- only review_fare_class_claim() sets it, and only to '
  '''discounted'' on approval. Defaults ''standard'' and is never reset back '
  'automatically; a revocation would be a future admin action, not built here.';

-- ---------------------------------------------------------------------------
-- The claim itself
-- ---------------------------------------------------------------------------
create table public.fare_class_claims (
  id                     uuid primary key default gen_random_uuid(),
  profile_id             uuid not null references public.profiles (id),
  -- Denormalized at submission time, same idiom as complaints/trip_ratings'
  -- display-name columns -- lets admin_web read a plain SELECT with no join.
  claimant_display_name  text not null,
  requested_class        text not null check (requested_class in ('student', 'senior_citizen', 'pwd')),
  id_photo_path          text not null,
  status                 text not null default 'pending_review'
    check (status in ('pending_review', 'approved', 'rejected')),
  rejection_reason       text,
  reviewed_by            uuid references public.profiles (id),
  reviewed_at            timestamptz,
  created_at             timestamptz not null default now(),
  constraint fare_class_claims_rejection_reason_required
    check (status <> 'rejected' or rejection_reason is not null)
);

-- Mirrors trips_one_active_per_rider's shape: one PENDING claim at a time
-- per commuter, not one claim ever -- a rejected claim must be resubmittable
-- with a fresh photo.
create unique index fare_class_claims_one_pending_per_profile
  on public.fare_class_claims (profile_id)
  where status = 'pending_review';

create index fare_class_claims_status_created_idx
  on public.fare_class_claims (status, created_at desc);

comment on table public.fare_class_claims is
  'Student/Senior Citizen/PWD discount claims. id_photo_path points into the '
  'discount-eligibility-ids bucket under the claimant''s own auth.uid() '
  'folder. Manual review only -- no automatic ID reading, see the file '
  'header comment.';

alter table public.fare_class_claims enable row level security;

create policy fare_class_claims_select_own_or_admin
  on public.fare_class_claims for select
  to authenticated
  using (
    profile_id = (select auth.uid())
    or public.is_admin((select auth.uid()))
  );

-- No insert/update policy: the two RPCs below are the only writers.

create or replace function public.submit_fare_class_claim(
  p_class text,
  p_id_photo_path text
)
returns public.fare_class_claims
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claimant public.profiles%rowtype;
  v_claim public.fare_class_claims%rowtype;
begin
  if p_class not in ('student', 'senior_citizen', 'pwd') then
    raise exception 'unrecognised fare class' using errcode = '22023';
  end if;

  if nullif(trim(coalesce(p_id_photo_path, '')), '') is null then
    raise exception 'an ID photo is required' using errcode = '22023';
  end if;

  -- Defense in depth: the Storage insert policy already restricts uploads
  -- to the caller's own auth.uid() folder, so a path outside it could not
  -- have been legitimately uploaded by this caller -- but nothing stops a
  -- client from simply typing a different string here, so this checks it is
  -- at least shaped like the caller's own path before ever storing it.
  if p_id_photo_path !~ ('^' || auth.uid()::text || '/') then
    raise exception 'the photo path must be under your own account'
      using errcode = '42501';
  end if;

  if exists (
    select 1 from public.fare_class_claims
     where profile_id = auth.uid() and status = 'pending_review'
  ) then
    raise exception 'you already have a claim pending review'
      using errcode = '22023';
  end if;

  select * into v_claimant from public.profiles where id = auth.uid();

  insert into public.fare_class_claims (
    profile_id, claimant_display_name, requested_class, id_photo_path
  )
  values (auth.uid(), v_claimant.display_name, p_class, p_id_photo_path)
  returning * into v_claim;

  return v_claim;
end;
$$;

comment on function public.submit_fare_class_claim(text, text) is
  'Files a discount claim for the caller. Does not touch profiles.fare_class '
  '-- only review_fare_class_claim() does that, and only on approval.';

revoke execute on function public.submit_fare_class_claim(text, text)
  from public, anon, authenticated;
grant execute on function public.submit_fare_class_claim(text, text)
  to authenticated, service_role;

create or replace function public.review_fare_class_claim(
  p_claim_id uuid,
  p_approve boolean,
  p_rejection_reason text
)
returns public.fare_class_claims
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claim public.fare_class_claims%rowtype;
  v_new_status text;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'only an administrator can review a fare-class claim'
      using errcode = '42501';
  end if;

  select * into v_claim from public.fare_class_claims where id = p_claim_id for update;
  if not found then
    raise exception 'the claim does not exist' using errcode = 'P0002';
  end if;
  if v_claim.status <> 'pending_review' then
    raise exception 'this claim has already been reviewed'
      using errcode = '22023';
  end if;

  if p_approve then
    v_new_status := 'approved';
    update public.fare_class_claims
       set status = v_new_status, reviewed_by = auth.uid(), reviewed_at = now()
     where id = p_claim_id
     returning * into v_claim;

    -- The one line that makes approval mean something: the next booking
    -- this profile makes is actually billed at the discounted rate.
    update public.profiles set fare_class = 'discounted' where id = v_claim.profile_id;
  else
    if nullif(trim(coalesce(p_rejection_reason, '')), '') is null then
      raise exception 'a rejection reason is required' using errcode = '22023';
    end if;
    v_new_status := 'rejected';
    update public.fare_class_claims
       set status = v_new_status,
           rejection_reason = trim(p_rejection_reason),
           reviewed_by = auth.uid(),
           reviewed_at = now()
     where id = p_claim_id
     returning * into v_claim;
  end if;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, metadata)
  values (
    auth.uid(),
    'fare_class_claim.' || v_new_status,
    v_claim.profile_id,
    jsonb_build_object('claim_id', v_claim.id, 'requested_class', v_claim.requested_class)
  );

  return v_claim;
end;
$$;

comment on function public.review_fare_class_claim(uuid, boolean, text) is
  'Admin-only. Approving sets profiles.fare_class = ''discounted'', which '
  'request_ride() bills against on the very next booking. Writes one '
  'admin_audit_logs row per decision. A claim already decided cannot be '
  're-decided through this function.';

revoke execute on function public.review_fare_class_claim(uuid, boolean, text)
  from public, anon, authenticated;
grant execute on function public.review_fare_class_claim(uuid, boolean, text)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- request_ride(): the ONLY change is which fare_class gets billed
-- ---------------------------------------------------------------------------
-- Every other line is copied verbatim from 20260831130000_phone_verification.sql
-- (the current definition -- confirmed by grepping every
-- `create or replace function public.request_ride` in supabase/migrations/
-- and taking the latest). CLAUDE.md rule 13: surgical changes only -- this
-- touches exactly the one line that reads 'standard' where it should read
-- the rider's actual fare_class.
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
    -- CHANGED (was the literal 'standard'): bill whatever fare_class the
    -- rider actually holds -- 'discounted' once an admin has approved a
    -- fare_class_claims row for them, 'standard' otherwise (the column
    -- default). Everything else in this function is unchanged.
    public.compute_fare(v_distance, 'special', v_rider.fare_class, 1),
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
