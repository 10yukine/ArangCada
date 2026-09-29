-- Verification-code resend schedule, enforced where it cannot be skipped.
--
-- Per mobile number, within one hour of the first code:
--   send 1 -> wait 60 s -> send 2 -> wait 120 s -> send 3 -> wait 120 s ->
--   send 4 -> no more until that first code is an hour old.
-- The existing 15-per-day number cap and 20-per-hour IP cap stay.
--
-- Until now record_otp_send() was only a courtesy: it ran when the app chose
-- to call it, and anyone could ask Supabase Auth for another SMS directly.
-- Now record_otp_send() issues a short-lived permit, and the Send SMS Hook
-- (supabase/functions/send-sms-hook) spends one before delivering anything,
-- so every SMS -- whatever asked for it -- goes through this schedule.
-- Existing app builds keep working: they already call record_otp_send()
-- before every send and show its message as written.
-- Regression: supabase/tests/88_otp_resend_schedule_test.sql.

alter table public.otp_send_log add column if not exists consumed_at timestamptz;
update public.otp_send_log set consumed_at = created_at where consumed_at is null;

-- "+" and digits, so "+639171234567" (app) and "639171234567" (Auth) match,
-- and the hash equals the one earlier rows were stored under.
create or replace function public.otp_phone_hash(p_phone text)
returns text
language sql
immutable
set search_path = ''
as $$
  select encode(pg_catalog.sha256(convert_to(
    '+' || regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 'UTF8')), 'hex');
$$;

-- Seconds until this number may receive another code (0 = now), and how many
-- of the four codes in the current hour are left.
create or replace function public.otp_schedule(p_phone_hash text)
returns table (wait_seconds integer, sends_left integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hour_count integer;
  v_first      timestamptz;
  v_last       timestamptz;
  v_day_count  integer;
  v_day_oldest timestamptz;
  v_ready      timestamptz;
begin
  select count(*), min(created_at), max(created_at)
    into v_hour_count, v_first, v_last
    from public.otp_send_log
   where phone_hash = p_phone_hash
     and created_at > now() - interval '1 hour';

  select count(*), min(created_at)
    into v_day_count, v_day_oldest
    from public.otp_send_log
   where phone_hash = p_phone_hash
     and created_at > now() - interval '24 hours';

  if v_day_count >= 15 then
    v_ready := v_day_oldest + interval '24 hours';
  elsif v_hour_count >= 4 then
    v_ready := v_first + interval '1 hour';
  elsif v_hour_count >= 1 then
    v_ready := v_last + case when v_hour_count = 1 then interval '60 seconds'
                             else interval '120 seconds' end;
  end if;

  wait_seconds := greatest(0, ceil(extract(epoch from coalesce(v_ready, now()) - now())))::integer;
  sends_left := greatest(0, least(4 - v_hour_count, 15 - v_day_count));
  return next;
end;
$$;

revoke execute on function public.otp_schedule(text) from public, anon, authenticated;

-- What the app shows under the code boxes: the live countdown and whether
-- another code is possible this hour.
create or replace function public.otp_resend_status(p_phone text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('wait_seconds', s.wait_seconds, 'sends_left', s.sends_left)
    from public.otp_schedule(public.otp_phone_hash(p_phone)) s
   where auth.uid() is not null;
$$;

revoke execute on function public.otp_resend_status(text) from public, anon;
grant execute on function public.otp_resend_status(text) to authenticated;

create or replace function public.record_otp_send(p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_phone_hash text := public.otp_phone_hash(p_phone);
  v_headers    json;
  v_ip         text;
  v_xff_parts  text[];
  v_ip_hash    text;
  v_wait       integer;
  v_left       integer;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  -- One request per number at a time, so two taps cannot both pass the check.
  perform pg_advisory_xact_lock(hashtextextended(v_phone_hash, 0));

  select wait_seconds, sends_left into v_wait, v_left
    from public.otp_schedule(v_phone_hash);
  if v_wait > 0 and v_left = 0 then
    raise exception 'You have used all your codes for now. Try again in % min.',
      greatest(1, ceil(v_wait / 60.0)::integer)
      using errcode = '22023';
  elsif v_wait > 0 then
    raise exception 'Please wait % seconds before requesting another code.', v_wait
      using errcode = '22023';
  end if;

  -- Client IP (Cloudflare first, then the proxy chain), hashed, never stored raw.
  v_headers := nullif(current_setting('request.headers', true), '')::json;
  if v_headers is not null then
    v_ip := nullif(btrim(coalesce(v_headers ->> 'cf-connecting-ip', '')), '');
    if v_ip is null then
      v_ip := nullif(btrim(coalesce(v_headers ->> 'x-real-ip', '')), '');
    end if;
    if v_ip is null then
      v_xff_parts := string_to_array(coalesce(v_headers ->> 'x-forwarded-for', ''), ',');
      if v_xff_parts is not null and array_length(v_xff_parts, 1) > 0 then
        v_ip := nullif(btrim(v_xff_parts[array_length(v_xff_parts, 1)]), '');
      end if;
    end if;
  end if;
  v_ip_hash := case when v_ip is null then null
                    else encode(pg_catalog.sha256(convert_to(v_ip, 'UTF8')), 'hex') end;

  if v_ip_hash is not null and (
    select count(*) from public.otp_send_log
     where ip_hash = v_ip_hash and created_at > now() - interval '1 hour'
  ) >= 20 then
    raise exception 'Too many code requests from this network. Try again later.'
      using errcode = '22023';
  end if;

  -- The permit the Send SMS Hook spends (consumed_at) before it delivers.
  insert into public.otp_send_log (user_id, phone_hash, ip_hash)
  values (v_uid, v_phone_hash, v_ip_hash);
  return true;
end;
$$;

revoke execute on function public.record_otp_send(text) from public, anon;
grant execute on function public.record_otp_send(text) to authenticated;

-- Called by the Send SMS Hook (service role) for every SMS Auth wants to
-- send. True only if this user requested a code for this number in the last
-- two minutes. A permit spent within the last 30 s is honoured again, so an
-- Auth retry of the same send is not refused.
create or replace function public.otp_consume_permit(p_user_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
begin
  select id into v_id
    from public.otp_send_log
   where user_id = p_user_id
     and phone_hash = public.otp_phone_hash(p_phone)
     and created_at > now() - interval '2 minutes'
     and (consumed_at is null or consumed_at > now() - interval '30 seconds')
   order by created_at desc
   limit 1
   for update;
  if v_id is null then
    return false;
  end if;
  update public.otp_send_log set consumed_at = coalesce(consumed_at, now()) where id = v_id;
  return true;
end;
$$;

revoke execute on function public.otp_consume_permit(uuid, text) from public, anon, authenticated;
grant execute on function public.otp_consume_permit(uuid, text) to service_role;
