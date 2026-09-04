-- Abandoning an unverified registration, and surviving the abuse it opens up.
--
-- Decided 4 Sep 2026. A user who mistypes their mobile number was stranded:
-- the code went to a number they do not hold, the account already existed, and
-- going back to registration failed with "already registered" against their own
-- email. The only escape was for an administrator to delete the row by hand.
--
-- Supabase Auth has no "verify, then create" flow -- signUp() writes the user
-- immediately, and even the phone-OTP path creates an unconfirmed user the
-- moment a code is sent. So rather than rebuild registration around a custom
-- pending table (which would mean an unauthenticated, user-creating,
-- credit-spending endpoint), the account is created as before and removed the
-- moment it is abandoned. The account exists for minutes instead of never,
-- which is a real difference, but it is the only part of the goal that
-- Supabase's own design forces us to give up.
--
-- Two exits, because there are two ways to abandon:
--   1. Deliberately -- "Go Back" on the verify screen calls
--      abandon_unverified_registration() and the email is instantly reusable.
--   2. By walking away -- the app is killed, so nothing calls anything.
--      sweep_abandoned_registrations() collects those later.

-- ---------------------------------------------------------------------------
-- The hole this opens, closed first
-- ---------------------------------------------------------------------------
-- otp_send_log.user_id references profiles ON DELETE CASCADE, and profiles
-- cascades from auth.users. So deleting an abandoned account also deletes its
-- OTP send history -- which is the throttle's entire memory.
--
-- Before this migration that was harmless, because accounts were never deleted.
-- With a self-service delete it becomes a bypass: register, request a code,
-- abandon, register again, request another code, forever. The per-account
-- throttle would reset every single time.
--
-- The log must therefore outlive the account. user_id becomes nullable and the
-- foreign key becomes ON DELETE SET NULL, so the row survives with its hashes
-- intact and the number- and IP-based limits below keep counting.

alter table public.otp_send_log
  alter column user_id drop not null;

alter table public.otp_send_log
  drop constraint if exists otp_send_log_user_id_fkey;

alter table public.otp_send_log
  add constraint otp_send_log_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete set null;

-- Hashed, never raw. Rule 10 forbids storing a phone number, and an IP address
-- is personal data under RA 10173 for exactly the same reason. A hash still
-- counts, which is all a throttle needs.
alter table public.otp_send_log
  add column if not exists ip_hash text;

comment on column public.otp_send_log.ip_hash is
  'SHA-256 of the client IP, for rate limiting. Never the address itself.';

-- The counting queries below filter on these, not on user_id.
create index if not exists otp_send_log_phone_time_idx
  on public.otp_send_log (phone_hash, created_at desc);

create index if not exists otp_send_log_ip_time_idx
  on public.otp_send_log (ip_hash, created_at desc);

-- ---------------------------------------------------------------------------
-- Throttle, re-cut to survive account deletion
-- ---------------------------------------------------------------------------
create or replace function public.record_otp_send(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_phone_hash text;
  v_ip_hash    text;
  v_ip         text;
  v_recent     integer;
  v_hourly     integer;
  v_daily      integer;
  v_ip_hourly  integer;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  v_phone_hash := encode(sha256(coalesce(p_phone, '')::bytea), 'hex');

  -- PostgREST exposes the request headers to SQL. x-forwarded-for may carry a
  -- proxy chain; the client is the first entry. Absent when called from a
  -- trusted server context rather than a device, in which case the IP limits
  -- simply do not apply -- they are anti-abuse for anonymous traffic, not an
  -- authorisation control.
  v_ip := split_part(
    coalesce(
      current_setting('request.headers', true)::json ->> 'x-forwarded-for',
      ''
    ),
    ',',
    1
  );
  v_ip := nullif(btrim(v_ip), '');
  v_ip_hash := case
                 when v_ip is null then null
                 else encode(sha256(v_ip::bytea), 'hex')
               end;

  -- 1. One per minute, per NUMBER rather than per account. Keyed on the number
  --    because the account is now disposable: deleting it and registering again
  --    used to reset a per-account counter instantly.
  select count(*) into v_recent
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '60 seconds';

  if v_recent > 0 then
    raise exception 'please wait a minute before requesting another code'
      using errcode = '22023';
  end if;

  -- 2. Five an hour to one number. Matches the cooldown the client shows.
  select count(*) into v_hourly
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '1 hour';

  if v_hourly >= 5 then
    raise exception 'too many code requests, try again later'
      using errcode = '22023';
  end if;

  -- 3. Fifteen a day to one number. An hourly cap alone still allows 120 in a
  --    day, which is a real bill once the hook leaves stub mode.
  select count(*) into v_daily
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '24 hours';

  if v_daily >= 15 then
    raise exception 'too many code requests for this number today'
      using errcode = '22023';
  end if;

  -- 4. Twenty an hour from one address, across every number and account.
  --    Without this the per-number limits are trivially defeated by walking
  --    through numbers -- each one is under its own cap, and the total is
  --    unbounded. This is the limit that actually protects the SMS balance.
  if v_ip_hash is not null then
    select count(*) into v_ip_hourly
      from public.otp_send_log
     where ip_hash = v_ip_hash
       and created_at > now() - interval '1 hour';

    if v_ip_hourly >= 20 then
      raise exception 'too many code requests, try again later'
        using errcode = '22023';
    end if;
  end if;

  insert into public.otp_send_log (user_id, phone_hash, ip_hash)
  values (v_uid, v_phone_hash, v_ip_hash);

  return true;
end;
$$;

comment on function public.record_otp_send(text) is
  'Throttles OTP sends: one per 60s and five per hour and fifteen per day per '
  'NUMBER, plus twenty per hour per client IP. Keyed on hashes of the number '
  'and address rather than on the account, because an unverified account is '
  'now deletable and a per-account counter would reset on re-registration. '
  'Raises rather than returning false so a caller cannot ignore it.';

revoke execute on function public.record_otp_send(text) from public, anon;
grant execute on function public.record_otp_send(text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Exit 1: the user goes back
-- ---------------------------------------------------------------------------
create or replace function public.abandon_unverified_registration()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_phone  timestamptz;
  v_tester boolean;
  v_role   public.user_role;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select u.phone_confirmed_at into v_phone
    from auth.users u where u.id = v_uid;

  select p.is_internal_tester, p.role into v_tester, v_role
    from public.profiles p where p.id = v_uid;

  -- The whole guard. A confirmed number means this is a real account, not an
  -- abandoned registration, and this function must never be a "delete my
  -- account" endpoint reachable by accident. Deleting an account with data in
  -- it is a different feature with different consent requirements.
  if v_phone is not null then
    raise exception 'this account is already verified'
      using errcode = '42501';
  end if;

  -- Internal testers deliberately bypass verification, so phone_confirmed_at
  -- is null for them permanently. Without this they could delete themselves by
  -- tapping Go Back, and they are the fixtures every QA run depends on.
  if coalesce(v_tester, false) then
    raise exception 'internal tester accounts cannot be abandoned'
      using errcode = '42501';
  end if;

  -- Admins never register through the mobile app, so reaching this with an
  -- admin session means something has gone wrong. Refuse rather than delete.
  if v_role = 'admin' then
    raise exception 'administrator accounts cannot be abandoned'
      using errcode = '42501';
  end if;

  -- Cascades to profiles, and from there to every table that references it.
  -- otp_send_log is the deliberate exception: its foreign key was changed to
  -- ON DELETE SET NULL above so the throttle history survives this.
  delete from auth.users where id = v_uid;
end;
$$;

comment on function public.abandon_unverified_registration() is
  'Deletes the caller''s own account, but only while it has never confirmed a '
  'mobile number. Lets a user who mistyped their number go back and register '
  'again immediately instead of being locked out by their own email address. '
  'Refuses for verified accounts, internal testers and administrators.';

revoke execute on function public.abandon_unverified_registration() from public, anon;
grant execute on function public.abandon_unverified_registration() to authenticated;

-- ---------------------------------------------------------------------------
-- Exit 2: the user walks away
-- ---------------------------------------------------------------------------
create or replace function public.sweep_abandoned_registrations(
  p_older_than interval default interval '2 hours'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  with doomed as (
    select u.id
      from auth.users u
      join public.profiles p on p.id = u.id
     where u.phone_confirmed_at is null
       and u.created_at < now() - p_older_than
       and coalesce(p.is_internal_tester, false) = false
       and p.role in ('commuter', 'driver')
       -- Belt and braces. An unverified account cannot book -- request_ride
       -- refuses it -- so this should always be empty. If it is ever not, the
       -- assumption is wrong somewhere and deleting trip history would be the
       -- worst possible way to discover that.
       and not exists (
         select 1 from public.trips t
          where t.rider_id = u.id or t.driver_id = u.id
       )
  )
  delete from auth.users u using doomed d where u.id = d.id;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.sweep_abandoned_registrations(interval) is
  'Deletes accounts that never confirmed a mobile number and are older than the '
  'given age. Covers the user who kills the app mid-verification, where nothing '
  'can call abandon_unverified_registration(). Never touches internal testers, '
  'administrators, or any account with trip history. Two hours by default, so a '
  'user who reopens the app can still finish verifying.';

revoke execute on function public.sweep_abandoned_registrations(interval)
  from public, anon, authenticated;
grant execute on function public.sweep_abandoned_registrations(interval) to service_role;

-- Scheduling is optional and guarded: pg_cron is not enabled on every Supabase
-- project, and a migration that hard-fails on a missing extension would block
-- every later migration behind it. When absent, the function still exists and
-- can be run by hand or scheduled from the dashboard later.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    perform cron.unschedule('sweep-abandoned-registrations')
      where exists (
        select 1 from cron.job where jobname = 'sweep-abandoned-registrations'
      );

    perform cron.schedule(
      'sweep-abandoned-registrations',
      '17 * * * *',
      $cron$select public.sweep_abandoned_registrations()$cron$
    );
  else
    raise notice
      'pg_cron unavailable; sweep_abandoned_registrations() must be scheduled manually';
  end if;
end
$$;
