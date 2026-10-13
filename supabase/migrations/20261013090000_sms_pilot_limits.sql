-- Text messages stay inside what the school, the City and the telcos were told.
--
-- Semaphore request #29111, sender name "Arangcada". The school's endorsement
-- and the City of Calamba's authorization commit the pilot to: one-time codes
-- only; about 100 recipients, pilot testers; sent from 5 Oct 2026 to
-- 31 Jul 2027, and no later than 30 Sep 2027. The owner's budget is PHP 1,500
-- a month, and a priority text costs about PHP 1.12.
--
-- Until now the only limits were per number and per network address
-- (20260929030000). Sign-up is public, so nothing held the number of
-- recipients, the texts in a month or the last day.
--
-- sms_send_permit() is what the Send SMS Hook calls in live mode, in place of
-- otp_consume_permit(). It spends the same permit record_otp_send() issued,
-- then holds the send to four limits the owner sets:
--
--   max_sms_recipients       different numbers ever texted           125
--   max_numbers_per_account  numbers one account may text, 30 days     3
--   max_sms_per_month        texts in any 30 days                   1000
--   sms_until                the last day a text is sent      2027-07-31
--
-- A number that has been texted before does not count as a new recipient, so
-- a tester can still get a code after the list is full. A send is counted
-- when it is permitted, before Semaphore answers: a text that then fails still
-- counts, which errs on the side of the promise. Emailed codes are neither
-- counted nor limited here.
--
-- The limits live in phone_verification_settings, which no account can read
-- or change through the API. In the SQL editor, for the second stage:
--   update public.phone_verification_settings set max_sms_recipients = 550;
-- Raise it only after Semaphore, the school and the City have been told the
-- larger number.
--
-- Order: apply this first, then deploy the function. The hook already
-- deployed goes on calling otp_consume_permit(), which is unchanged.
--
-- Regression: supabase/tests/102_sms_pilot_limits_test.sql
alter table public.phone_verification_settings
  add column max_sms_recipients integer not null default 125
    check (max_sms_recipients >= 0),
  add column max_numbers_per_account integer not null default 3
    check (max_numbers_per_account >= 1),
  add column max_sms_per_month integer not null default 1000
    check (max_sms_per_month >= 0),
  add column sms_until date not null default date '2027-07-31';

comment on table public.phone_verification_settings is
  'One row. sms_live_since is written only by begin_phone_reverification(); the text limits are changed by the owner in the SQL editor.';

-- The send log outlives the account (20260904020000), so these counts cannot
-- be reset by deleting an account and registering again.
alter table public.otp_send_log add column sms_sent_at timestamptz;

comment on column public.otp_send_log.sms_sent_at is
  'When this request was permitted to go out as a text message. Null for a code that was emailed, or never sent.';

create function public.sms_send_permit(p_user_id uuid, p_phone text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash   text := public.otp_phone_hash(p_phone);
  v_limits public.phone_verification_settings%rowtype;
  v_row    public.otp_send_log%rowtype;
begin
  -- One decision at a time, so two sends cannot both take the last place.
  perform pg_advisory_xact_lock(hashtextextended('sms_send_permit', 0));

  -- The permit, exactly as otp_consume_permit() finds it.
  select * into v_row
    from public.otp_send_log
   where user_id = p_user_id
     and phone_hash = v_hash
     and created_at > now() - interval '2 minutes'
     and (consumed_at is null or consumed_at > now() - interval '30 seconds')
   order by created_at desc
   limit 1
   for update;
  if not found then
    return 'no_permit';
  end if;

  -- Auth sending the same text again within the 30 seconds: already counted.
  if v_row.sms_sent_at is not null then
    return 'ok';
  end if;

  select * into v_limits from public.phone_verification_settings where id;

  if (now() at time zone 'Asia/Manila')::date > v_limits.sms_until then
    return 'ended';
  end if;

  if (select count(*) from public.otp_send_log
       where sms_sent_at > now() - interval '30 days') >= v_limits.max_sms_per_month then
    return 'month_cap';
  end if;

  if not exists (select 1 from public.otp_send_log
                  where phone_hash = v_hash and sms_sent_at is not null)
     and (select count(distinct phone_hash) from public.otp_send_log
           where sms_sent_at is not null) >= v_limits.max_sms_recipients then
    return 'recipient_cap';
  end if;

  if (select count(distinct phone_hash) from public.otp_send_log
       where user_id = p_user_id
         and phone_hash <> v_hash
         and sms_sent_at > now() - interval '30 days') >= v_limits.max_numbers_per_account then
    return 'account_cap';
  end if;

  update public.otp_send_log
     set consumed_at = coalesce(consumed_at, now()), sms_sent_at = now()
   where id = v_row.id;
  return 'ok';
end;
$$;

comment on function public.sms_send_permit(uuid, text) is
  'For the Send SMS Hook in live mode: spends the permit and holds the text to the pilot limits. Returns ok, or no_permit, ended, month_cap, recipient_cap, account_cap.';

revoke execute on function public.sms_send_permit(uuid, text) from public, anon, authenticated;
grant execute on function public.sms_send_permit(uuid, text) to service_role;
