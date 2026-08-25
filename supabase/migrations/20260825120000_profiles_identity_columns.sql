-- Make phone and email identity-bearing columns on profiles.
--
-- WHY
--
-- Driver onboarding resolves a person by mobile number or email: the admin
-- types one, the system finds the account, and a role change follows. That
-- makes both columns authorization-adjacent, and both were unfit for it:
--
--   phone  text          -- nullable, not unique, no format
--   email                -- did not exist at all; email lived only in auth.users
--
-- An admin typing a number into a promotion screen, against a column with no
-- uniqueness guarantee, is a promote-the-wrong-account bug waiting to happen.
-- The "one account per mobile number" rule the onboarding design depends on
-- is also unenforceable without a unique constraint.
--
-- DEVIATION FROM SPEC (recorded in .pipeline/changes.md)
--
-- .pipeline/specs.md planned phone (20260825120000) and email
-- (20260825120800) as separate migrations, because email arrived with the
-- later addendum. They are merged here: both are the same concern, both are
-- read by the same signup trigger, and splitting them would mean defining
-- handle_new_user() twice in one session for no benefit -- nothing is
-- deployed yet, so there is no migration history to preserve.
--
-- NOTE ON NORMALISATION
--
-- Formatting variance is the enemy of duplicate detection. 0917 000 0000,
-- +639170000000, and 639170000000 are one number written three ways; stored
-- verbatim they are three distinct rows and the "already has an account"
-- check silently misses. Everything is normalised to E.164 on the way in,
-- through one function both the trigger and the onboarding RPCs share.

-- ---------------------------------------------------------------------------
-- Philippine mobile number normalisation
-- ---------------------------------------------------------------------------
-- Returns null for anything that is not a recognisable PH mobile number, so
-- callers can decide whether that is a hard error (the signup trigger) or a
-- simple no-match (an admin lookup). Deliberately does NOT raise: a lookup
-- for a malformed number should return "not found", not crash the request.
create or replace function public.normalize_ph_mobile(p_raw text)
returns text
language sql
immutable
as $$
  with stripped as (
    select regexp_replace(coalesce(p_raw, ''), '[^0-9+]', '', 'g') as v
  )
  select case
           -- already canonical
           when v ~ '^\+639[0-9]{9}$' then v
           -- missing the leading +
           when v ~ '^639[0-9]{9}$'   then '+' || v
           -- local trunk-prefixed form, the way it is written on a jeepney sign
           when v ~ '^09[0-9]{9}$'    then '+63' || substring(v from 2)
           -- bare subscriber number
           when v ~ '^9[0-9]{9}$'     then '+63' || v
           else null
         end
    from stripped;
$$;

comment on function public.normalize_ph_mobile(text) is
  'Normalises a Philippine mobile number to E.164 (+639XXXXXXXXX). Returns '
  'null when the input is not a recognisable PH mobile number. Shared by the '
  'signup trigger and the driver onboarding lookups so both normalise '
  'identically and a lookup can never miss on formatting alone.';

-- ---------------------------------------------------------------------------
-- email
-- ---------------------------------------------------------------------------
-- Denormalised from auth.users deliberately. The alternative -- joining to
-- auth.users on every lookup -- means an RLS-protected public table depending
-- on a schema clients cannot read, and it puts an auth-schema join inside
-- every security definer function that resolves a person. A synced copy with
-- a unique constraint is simpler and lets duplicate detection be an ordinary
-- index lookup. 20260825120050_handle_new_user.sql keeps it current.
alter table public.profiles add column email text;

-- ---------------------------------------------------------------------------
-- Backfill and normalise whatever is already here
-- ---------------------------------------------------------------------------
update public.profiles p
   set phone = public.normalize_ph_mobile(p.phone),
       email = lower(u.email)
  from auth.users u
 where u.id = p.id;

-- ---------------------------------------------------------------------------
-- Fail loudly rather than silently choosing a winner
-- ---------------------------------------------------------------------------
-- If real rows exist that cannot satisfy the constraints below, that is a data
-- problem a human must look at. Picking one row of a duplicate pair, or
-- inventing a placeholder number, would corrupt exactly the identity guarantee
-- this migration exists to establish. On a fresh local database this block is
-- a no-op: supabase/seed.sql seeds no profiles rows.
do $$
declare
  v_null_phone int;
  v_dup_phone  int;
  v_null_email int;
  v_dup_email  int;
begin
  select count(*) into v_null_phone
    from public.profiles where phone is null;

  select count(*) into v_dup_phone
    from (select phone from public.profiles
           where phone is not null
           group by phone having count(*) > 1) d;

  select count(*) into v_null_email
    from public.profiles where email is null;

  select count(*) into v_dup_email
    from (select email from public.profiles
           where email is not null
           group by email having count(*) > 1) d;

  if v_null_phone > 0 or v_dup_phone > 0
     or v_null_email > 0 or v_dup_email > 0 then
    raise exception using
      errcode = '23514',
      message = 'profiles identity backfill incomplete',
      detail  = format(
        '%s row(s) have no usable phone, %s phone value(s) are duplicated, %s row(s) have no email, %s email value(s) are duplicated.',
        v_null_phone, v_dup_phone, v_null_email, v_dup_email),
      hint    = 'Resolve these rows by hand before re-running. This migration will not guess which duplicate to keep.';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------------------
alter table public.profiles
  alter column phone set not null,
  alter column email set not null,
  add constraint profiles_phone_e164
    check (phone ~ '^\+639[0-9]{9}$'),
  -- Stored lowercase so uniqueness is genuinely case-insensitive. Without
  -- this, Juan@example.test and juan@example.test are two accounts and the
  -- duplicate check misses.
  add constraint profiles_email_normalised
    check (email = lower(email) and email like '%@%');

create unique index profiles_phone_key on public.profiles (phone);
create unique index profiles_email_key on public.profiles (email);

comment on column public.profiles.phone is
  'E.164 Philippine mobile number, unique. Identity-bearing: the driver '
  'onboarding flow resolves a person by this value.';

comment on column public.profiles.email is
  'Lowercased copy of auth.users.email, unique. Kept current by '
  'handle_new_user() and sync_profile_email(). Identity-bearing, same as phone.';
