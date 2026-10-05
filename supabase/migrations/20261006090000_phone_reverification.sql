-- Moving the one-time code from email to text message without losing accounts.
--
-- While SMS_HOOK_MODE is `email` the code that "verifies a number" goes to the
-- account's email, so phone_verified_at proves the mailbox and nothing about
-- the number. When the hook goes `live`, every number confirmed before that
-- has to be confirmed again, by text. Clearing the confirmation alone would
-- destroy accounts in two ways (release audit, 2 and 5 Oct 2026):
--
--   * sweep_abandoned_registrations() deletes an unverified rider with no
--     trips about two hours later, as an abandoned sign-up;
--   * "Go back" on the app's verify screen calls
--     abandon_unverified_registration(), which deletes the account.
--
-- This migration changes nothing by itself. It adds:
--
--   * profiles.phone_reverify_since -- set on an account that was asked to
--     confirm its number again. The sweep and the abandon function leave such
--     an account alone from then on: it is an established account, not a
--     registration in progress.
--   * phone_verification_settings.sms_live_since -- when codes began to go by
--     text. Null until then.
--   * begin_phone_reverification() -- run once, by the owner, after the hook
--     is live and a real text has arrived. It marks every account whose number
--     was confirmed before that moment and clears the confirmation, so the app
--     sends each of them to its verify screen. Safe to run again.
--   * email_is_proved() -- before the switch a verified account has proved its
--     mailbox, because the code was emailed. After it only the confirmation
--     link (20261005130000) does, so enrolling a driver by email asks for
--     that. Supabase Auth's own "Confirm email" can stay off.
--
-- Regression: supabase/tests/101_phone_reverification_test.sql

alter table public.profiles add column phone_reverify_since timestamptz;

comment on column public.profiles.phone_reverify_since is
  'Set by begin_phone_reverification() on an account asked to confirm its '
  'number again by text. Never cleared: it also marks the account as one the '
  'abandoned-registration sweep must not delete.';

create table public.phone_verification_settings (
  id boolean primary key default true check (id),
  -- When one-time codes began to be sent by text message. Null while they
  -- are emailed.
  sms_live_since timestamptz
);

comment on table public.phone_verification_settings is
  'One row. Written only by begin_phone_reverification().';

insert into public.phone_verification_settings default values;

alter table public.phone_verification_settings enable row level security;
revoke all on public.phone_verification_settings from public, anon, authenticated;

create function public.email_is_proved(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_verified_account(p_uid)
     and exists (
       select 1
         from public.profiles p
        where p.id = p_uid
          and (
            p.email_confirmed_at is not null
            or (select s.sms_live_since is null
                  from public.phone_verification_settings s)
          )
     );
$$;

revoke all on function public.email_is_proved(uuid) from public, anon, authenticated;

-- Patched in place, as 20261002130000 does. Each anchor must occur exactly
-- once or the migration aborts and changes nothing.
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.sweep_abandoned_registrations(interval)',
       'and coalesce(p.is_internal_tester, false) = false',
       'and coalesce(p.is_internal_tester, false) = false
       -- Asked to confirm its number again by text (20261006090000): an
       -- established account, never an abandoned registration.
       and p.phone_reverify_since is null'),
      ('public.abandon_unverified_registration()',
       'if coalesce(v_tester, false) then',
       'if exists (
    select 1 from public.profiles p
     where p.id = v_uid and p.phone_reverify_since is not null
  ) then
    raise exception ''this account is confirming its number again and cannot be abandoned''
      using errcode = ''42501'';
  end if;

  if coalesce(v_tester, false) then'),
      ('public.admin_preview_driver_candidate(text,text)',
       '(m.key = ''email'' and p.email = m.val and public.is_verified_account(p.id))',
       '(m.key = ''email'' and p.email = m.val and public.email_is_proved(p.id))'),
      ('public.admin_promote_commuter_to_driver(text,text,text,text,uuid,text,text)',
       'where email = v_email and public.is_verified_account(id);',
       'where email = v_email and public.email_is_proved(id);'),
      ('public.admin_create_driver_invite(text,uuid,text)',
       'if exists (select 1 from public.profiles where email = v_email) then',
       'if exists (
    select 1 from public.profiles
     where email = v_email and not public.email_is_proved(id)
  ) then
    raise exception ''this email belongs to an account that has not confirmed it -- ask the driver to confirm the email from the Profile screen in the app, or enrol them by mobile number''
      using errcode = ''23505'';
  end if;

  if exists (select 1 from public.profiles where email = v_email) then')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the phone re-verification migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;

-- The switch. Answers with the number of accounts sent to confirm again.
create function public.begin_phone_reverification()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_since timestamptz;
  v_ids   uuid[];
begin
  -- Nobody should lose the ability to finish a trip part-way through it.
  if exists (
    select 1 from public.trips
     where status not in ('completed', 'cancelled_by_rider',
                          'cancelled_by_driver', 'no_driver_available')
  ) then
    raise exception 'a trip is still open; run this when no trip is in progress'
      using errcode = '55000';
  end if;

  update public.phone_verification_settings
     set sms_live_since = coalesce(sms_live_since, now())
  returning sms_live_since into v_since;

  -- Everyone whose number was confirmed before codes went by text. A second
  -- run finds only accounts the first one missed.
  with marked as (
    update public.profiles
       set phone_reverify_since = v_since
     where phone_verified_at < v_since
    returning id
  )
  select coalesce(array_agg(id), '{}') into v_ids from marked;

  update public.driver_availability
     set is_online = false
   where driver_id = any (v_ids) and is_online;

  -- The number is cleared along with its confirmation because Auth sends no
  -- code for a number the account already holds. The trigger on auth.users
  -- then clears profiles.phone_verified_at; the number itself stays in
  -- profiles.phone and in the sign-up details, so the app can show it.
  update auth.users
     set phone = null, phone_confirmed_at = null
   where id = any (v_ids);

  return cardinality(v_ids);
end;
$$;

revoke all on function public.begin_phone_reverification() from public, anon, authenticated;
