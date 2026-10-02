-- One account must not be able to use up another person's verification codes
-- (release audit, 2 Oct 2026).
--
-- record_otp_send() issues the permit the Send SMS hook spends before a code
-- goes out. Its schedule (4 an hour, 15 a day, 60 s / 120 s apart) counted
-- every permit recorded for a number, by anyone, spent or not. So any signed-in
-- account could call it for someone else's number until the number had no
-- codes left, without a single SMS being sent, and keep it that way. The
-- number's owner could then not verify, could not book, and was deleted by the
-- abandoned-registration sweep after two hours.
--
-- The schedule a caller sees now counts only
--   * that caller's own requests for the number, and
--   * codes actually delivered to the number (the permit was spent).
-- Other accounts' unspent permits cost the owner nothing.
--
-- Because several accounts can now each hold a fresh permit for one number,
-- the per-number cap is enforced again where a permit is spent, so the number
-- still receives at most 4 codes an hour and 15 a day in total.
--
-- Not closed: someone who makes Auth really deliver codes to a number can
-- still use up its cap. Those sends are real messages the owner sees.
--
-- Regression: supabase/tests/88_otp_resend_schedule_test.sql.

create function public.otp_schedule(p_user_id uuid, p_phone_hash text)
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
     and (user_id = p_user_id or consumed_at is not null)
     and created_at > now() - interval '1 hour';

  select count(*), min(created_at)
    into v_day_count, v_day_oldest
    from public.otp_send_log
   where phone_hash = p_phone_hash
     and (user_id = p_user_id or consumed_at is not null)
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

revoke execute on function public.otp_schedule(uuid, text) from public, anon, authenticated;

-- Both callers keep the rest of their bodies. Each anchor must occur exactly
-- once or the migration aborts.
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.record_otp_send(text)',
       'public.otp_schedule(v_phone_hash)',
       'public.otp_schedule(v_uid, v_phone_hash)'),
      ('public.otp_resend_status(text)',
       'public.otp_schedule(public.otp_phone_hash(p_phone))',
       'public.otp_schedule(auth.uid(), public.otp_phone_hash(p_phone))')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the OTP budget migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;

drop function public.otp_schedule(text);

create or replace function public.otp_consume_permit(p_user_id uuid, p_phone text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash     text := public.otp_phone_hash(p_phone);
  v_id       bigint;
  v_consumed timestamptz;
begin
  -- The same lock record_otp_send takes, so two accounts spending permits for
  -- one number are counted one after the other.
  perform pg_advisory_xact_lock(hashtextextended(v_hash, 0));

  select id, consumed_at into v_id, v_consumed
    from public.otp_send_log
   where user_id = p_user_id
     and phone_hash = v_hash
     and created_at > now() - interval '2 minutes'
     and (consumed_at is null or consumed_at > now() - interval '30 seconds')
   order by created_at desc
   limit 1
   for update;
  if v_id is null then
    return false;
  end if;

  -- A permit already spent in the last 30 seconds is a retry of the same send.
  if v_consumed is null and (
       (select count(*) from public.otp_send_log
         where phone_hash = v_hash and consumed_at is not null
           and created_at > now() - interval '1 hour') >= 4
    or (select count(*) from public.otp_send_log
         where phone_hash = v_hash and consumed_at is not null
           and created_at > now() - interval '24 hours') >= 15
  ) then
    return false;
  end if;

  update public.otp_send_log set consumed_at = coalesce(consumed_at, now()) where id = v_id;
  return true;
end;
$$;
