-- Two findings from the adversarial review of 20260904020000, fixed.
--
-- FINDING 1 (HIGH) -- the IP cap was defeatable by the attacker it targets.
--
-- record_otp_send() read the client address as the FIRST entry of
-- x-forwarded-for. That entry is the one the client itself supplies: anyone
-- can send `X-Forwarded-For: 1.2.3.4` and choose their own identity, then send
-- a different value on the next request. The per-IP cap -- the only limit that
-- constrains an attacker walking through many different phone numbers, and
-- therefore the only thing protecting the SMS balance once the hook leaves stub
-- mode -- could be bypassed by adding one header.
--
-- Supabase Cloud sits behind Cloudflare, which OVERWRITES cf-connecting-ip with
-- the real peer address and cannot be forged by the client. That is the header
-- to trust. Where a proxy appends rather than overwrites, the trustworthy end
-- of x-forwarded-for is the LAST entry, not the first, so the fallback is taken
-- from that end.
--
-- FINDING 2 (HIGH) -- the sweep could delete an onboarded driver.
--
-- sweep_abandoned_registrations() deletes accounts with no confirmed phone and
-- no trips. A driver onboarded by an administrator who has not personally
-- completed SMS verification matches both conditions exactly, and a newly
-- approved driver has no trips yet by definition. The sweep would have deleted
-- them two hours later, cascading away their driver_profiles row and their
-- uploaded verification documents.
--
-- Any account with a driver_profiles row is now excluded outright. A driver
-- record only exists because an administrator created it, which is sufficient
-- evidence that the account is not an abandoned registration.

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
  v_headers    json;
  v_xff        text;
  v_xff_parts  text[];
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

  v_headers := nullif(current_setting('request.headers', true), '')::json;

  if v_headers is not null then
    -- Cloudflare sets this itself and discards any client-supplied copy, so it
    -- is the only entry here that an attacker cannot choose.
    v_ip := nullif(btrim(coalesce(v_headers ->> 'cf-connecting-ip', '')), '');

    if v_ip is null then
      v_ip := nullif(btrim(coalesce(v_headers ->> 'x-real-ip', '')), '');
    end if;

    if v_ip is null then
      v_xff := coalesce(v_headers ->> 'x-forwarded-for', '');
      v_xff_parts := string_to_array(v_xff, ',');
      if v_xff_parts is not null and array_length(v_xff_parts, 1) > 0 then
        -- LAST, not first. Each proxy appends the peer it actually saw, so the
        -- final entry is the one written by the hop closest to us. The first
        -- entry is whatever the client claimed before anyone verified it.
        v_ip := nullif(
          btrim(v_xff_parts[array_length(v_xff_parts, 1)]),
          ''
        );
      end if;
    end if;
  end if;

  v_ip_hash := case
                 when v_ip is null then null
                 else encode(sha256(v_ip::bytea), 'hex')
               end;

  select count(*) into v_recent
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '60 seconds';

  if v_recent > 0 then
    raise exception 'please wait a minute before requesting another code'
      using errcode = '22023';
  end if;

  select count(*) into v_hourly
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '1 hour';

  if v_hourly >= 5 then
    raise exception 'too many code requests, try again later'
      using errcode = '22023';
  end if;

  select count(*) into v_daily
    from public.otp_send_log
   where phone_hash = v_phone_hash
     and created_at > now() - interval '24 hours';

  if v_daily >= 15 then
    raise exception 'too many code requests for this number today'
      using errcode = '22023';
  end if;

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
  'Throttles OTP sends: one per 60s, five per hour and fifteen per day per '
  'NUMBER, plus twenty per hour per client IP. The address is read from '
  'cf-connecting-ip (set by Cloudflare, not forgeable by the client), falling '
  'back to x-real-ip and then to the LAST x-forwarded-for entry -- the first '
  'entry is client-supplied and would let an attacker pick a fresh identity per '
  'request. Both the number and the address are stored only as hashes.';

revoke execute on function public.record_otp_send(text) from public, anon;
grant execute on function public.record_otp_send(text) to authenticated, service_role;

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
       -- A driver record exists only because an administrator created it, which
       -- is enough to say the account is not an abandoned registration. Without
       -- this, a driver onboarded by an admin who never personally completed
       -- SMS verification matched every other condition -- and a newly approved
       -- driver has no trips yet by definition -- so the sweep would have
       -- deleted them, taking their verification documents with them.
       and not exists (
         select 1 from public.driver_profiles d where d.id = u.id
       )
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
  'given age. Never touches internal testers, administrators, accounts with a '
  'driver record, or accounts with trip history. Two hours by default so a user '
  'who reopens the app can still finish verifying.';

revoke execute on function public.sweep_abandoned_registrations(interval)
  from public, anon, authenticated;
grant execute on function public.sweep_abandoned_registrations(interval) to service_role;
