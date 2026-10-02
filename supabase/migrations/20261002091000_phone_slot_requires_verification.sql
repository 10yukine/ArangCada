-- A mobile number belongs to the account that proved it, not to the first
-- account that typed it (release audit, 2 Oct 2026).
--
-- profiles.phone was unique across every row, and handle_new_user() writes it
-- from signup metadata before anyone has received a code. Two things followed:
--
-- 1. Anyone could sign up with somebody else's number. The real owner's
--    registration then failed on profiles_phone_key, for as long as the
--    squatter kept signing up again after each sweep. No SIM was needed.
-- 2. When an account confirmed a number that another, unverified row was
--    sitting on, the mirror trigger could not write the number, and its
--    fallback recorded the confirmation time anyway. The account ended up
--    "verified" while profiles.phone still held the number it had typed at
--    signup, which it had never proved. Drivers were shown that number as the
--    rider's contact.
--
-- So uniqueness now applies to verified numbers only. An unverified claim
-- reserves nothing: whoever receives the code gets the number, and the other
-- claim can never be verified (auth.users.phone is unique) and is swept like
-- any abandoned registration.
--
-- Regression: supabase/tests/71_phone_number_mirror_test.sql and
-- 46_profiles_identity_test.sql.

drop index public.profiles_phone_key;
create unique index profiles_phone_key
  on public.profiles (phone)
  where phone_verified_at is not null;

comment on index public.profiles_phone_key is
  'One account per verified mobile number. Unverified signup claims are not '
  'unique: they prove nothing and must not block the number''s owner.';

-- The mirror can now only collide with another *verified* row. That should not
-- happen, because auth.users.phone is unique too; if it ever does, the account
-- must not be left verified for a number other than the one it confirmed.
create or replace function public.sync_profile_phone_verified()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text;
begin
  v_phone := nullif(btrim(coalesce(new.phone, '')), '');
  if v_phone is not null and left(v_phone, 1) <> '+' then
    v_phone := '+' || v_phone;
  end if;
  if v_phone !~ '^\+639[0-9]{9}$' then
    v_phone := null;
  end if;

  begin
    update public.profiles
       set phone_verified_at = new.phone_confirmed_at,
           phone = coalesce(v_phone, phone)
     where id = new.id
       and (
         phone_verified_at is distinct from new.phone_confirmed_at
         or phone is distinct from coalesce(v_phone, phone)
       );
  exception
    when unique_violation then
      -- Raising here would abort the confirmation in auth.users and show the
      -- user "wrong code". Leave the profile unverified instead.
      update public.profiles
         set phone_verified_at = null
       where id = new.id
         and phone_verified_at is not null;
  end;

  return new;
end;
$$;

comment on function public.sync_profile_phone_verified() is
  'Mirrors auth.users.phone_confirmed_at and auth.users.phone into '
  'profiles.phone_verified_at and profiles.phone. Restores the leading "+" '
  'that GoTrue omits. A number that is not a valid PH mobile is not mirrored. '
  'If another verified profile already holds the number, the profile is left '
  'unverified rather than verified for a number it did not confirm.';

-- The functions below look an account up by its number. An unverified claim
-- is no longer unique, so they read verified numbers only. Patched in place,
-- as 20260926154651 does; each anchor must occur exactly once.
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      -- A number a verified account holds is still refused at signup, as it
      -- was when the index covered every row.
      ('public.handle_new_user()',
       'insert into public.profiles (id, display_name, phone, email)',
       'if exists (
    select 1 from public.profiles p
     where p.phone = v_phone and p.phone_verified_at is not null
  ) then
    raise exception ''handle_new_user: that mobile number belongs to a verified account''
      using errcode = ''23505'';
  end if;

  insert into public.profiles (id, display_name, phone, email)'),
      ('public.admin_preview_driver_candidate(text,text)',
       '(m.key = ''phone'' and p.phone = m.val)',
       '(m.key = ''phone'' and p.phone = m.val and p.phone_verified_at is not null)'),
      ('public.admin_promote_commuter_to_driver(text,text,text,text,uuid,text,text)',
       'select id into v_target from public.profiles where phone = v_phone;',
       'select id into v_target from public.profiles
       where phone = v_phone and phone_verified_at is not null;')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the phone slot migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;
