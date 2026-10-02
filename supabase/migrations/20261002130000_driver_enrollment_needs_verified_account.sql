-- Only a verified account can be made a driver by its email (release audit
-- NV3, 2 Oct 2026).
--
-- The hosted project does not ask a new account to confirm its email, so
-- profiles.email is whatever was typed at sign-up. Someone who knew a driver's
-- email could register it first. The admin console then reported "This email
-- already has an account" and promoted that account to driver; the token-bound
-- invite, the only path that proves the mailbox, was refused because the
-- email was taken.
--
-- An account is verified once it has entered the one-time code. While
-- SMS_HOOK_MODE is `email` that code is sent to the account's email, so a
-- verified account has proved the mailbox. An account that never verifies is
-- deleted by sweep_abandoned_registrations() about two hours after sign-up.
--
--   * admin_preview_driver_candidate and admin_promote_commuter_to_driver no
--     longer match an unverified account by email (the phone match already
--     required verification, 20261002091000).
--   * admin_create_driver_invite says why it cannot invite that email yet,
--     instead of pointing at a promote flow that no longer offers it.
--
-- When the code moves to SMS it stops proving the mailbox. "Confirm email" has
-- to be switched on at that point; see the cutover plan in the release notes.
--
-- Patched in place, as 20261002091000 does. Each anchor must occur exactly
-- once or the migration aborts and changes nothing.
--
-- Regression: supabase/tests/93_driver_enrollment_needs_verified_account_test.sql
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.admin_preview_driver_candidate(text,text)',
       '(m.key = ''email'' and p.email = m.val)',
       '(m.key = ''email'' and p.email = m.val and public.is_verified_account(p.id))'),
      ('public.admin_promote_commuter_to_driver(text,text,text,text,uuid,text,text)',
       'select id into v_target from public.profiles where email = v_email;',
       'select id into v_target from public.profiles
       where email = v_email and public.is_verified_account(id);'),
      ('public.admin_create_driver_invite(text,uuid,text)',
       'if exists (select 1 from public.profiles where email = v_email) then',
       'if exists (
    select 1 from public.profiles
     where email = v_email and not public.is_verified_account(id)
  ) then
    raise exception ''this email has a sign-up that was never verified -- it is removed about two hours after it was started; send the invite after that''
      using errcode = ''23505'';
  end if;

  if exists (select 1 from public.profiles where email = v_email) then')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the driver enrollment migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;
