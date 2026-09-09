-- pgTAP: driver enrollment by email (Spec 20).
--
-- WHY THIS FILE EXISTS
--
-- driver_finalize_invited_account() is the only place a fresh profile ever
-- becomes a driver by way of an invite rather than a face-to-face promotion,
-- and it runs as service_role with no auth.uid() of its own -- the exact
-- shape 55_driver_onboarding_test.sql already established is worth testing
-- on its own for admin_activate_new_driver(). This file does the same for
-- its sibling. The token half (admin_create_driver_invite/
-- driver_invite_lookup/admin_revoke_driver_invite) mirrors
-- 77_admin_invites_test.sql closely on purpose -- same shape, same risks.

begin;

select plan(28);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000078c1', 'di-lgu@example.test',
     '{"display_name":"Di Lgu","mobile_number":"+639170007801"}'::jsonb),
  ('00000000-0000-0000-0000-0000000078c2', 'di-toda@example.test',
     '{"display_name":"Di Toda","mobile_number":"+639170007802"}'::jsonb),
  ('00000000-0000-0000-0000-0000000078a1', 'di-commuter@example.test',
     '{"display_name":"Di Commuter","mobile_number":"+639170007803"}'::jsonb);

update public.profiles set role = 'admin' where id in (
  '00000000-0000-0000-0000-0000000078c1', '00000000-0000-0000-0000-0000000078c2'
);

create temporary table di_zone as
  select id, name from public.toda_zones where is_active order by code limit 1;
grant select on di_zone to authenticated, service_role, anon;

create temporary table di_inactive_zone as
  select id from public.toda_zones where not is_active limit 1;
grant select on di_inactive_zone to authenticated, service_role;

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
values ('00000000-0000-0000-0000-0000000078c2', 'toda', (select id from di_zone));

-- ===========================================================================
-- admin_create_driver_invite
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078a1';

select throws_ok(
  $$select public.admin_create_driver_invite('someone@example.test', (select id from di_zone), null)$$,
  '42501', null,
  'a commuter cannot invite a driver'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078c2';

select throws_ok(
  $$select public.admin_create_driver_invite('someone@example.test', (select id from di_zone), null)$$,
  '42501', null,
  'a TODA-scoped admin cannot invite a driver -- LGU only, matching admin_promote_commuter_to_driver'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078c1';

select throws_ok(
  $$select public.admin_create_driver_invite('not-an-email', (select id from di_zone), null)$$,
  '22023', null,
  'a malformed email is rejected'
);

select throws_ok(
  $$select public.admin_create_driver_invite('someone@example.test', (select id from di_inactive_zone), null)$$,
  '23503', null,
  'an inactive TODA zone is rejected'
);

select throws_ok(
  $$select public.admin_create_driver_invite('di-commuter@example.test', (select id from di_zone), null)$$,
  '23505', null,
  'an email that already has an account is refused -- use the promote flow instead'
);

create temporary table di_token as
  select public.admin_create_driver_invite('di-recruit@example.test', (select id from di_zone), 'DI-001') as token;
grant select on di_token to authenticated, service_role, anon;

select is(
  (select char_length(token) from di_token), 64,
  'the returned raw token is 64 hex characters'
);

select is(
  (select count(*)::int from public.driver_invites
    where email = 'di-recruit@example.test' and status = 'pending'),
  1,
  'exactly one pending invite row was written'
);

select isnt(
  (select token_hash from public.driver_invites where email = 'di-recruit@example.test'),
  (select token from di_token),
  'the stored hash is not the raw token -- it is never kept in plaintext'
);

select is(
  (select count(*)::int from public.admin_audit_logs where action = 'driver_invite.created'),
  1,
  'invite creation wrote exactly one audit row'
);

-- Re-inviting the same email supersedes the first pending row.
create temporary table di_token2 as
  select public.admin_create_driver_invite('di-recruit@example.test', (select id from di_zone), null) as token;
grant select on di_token2 to authenticated, service_role, anon;

select is(
  (select count(*)::int from public.driver_invites
    where email = 'di-recruit@example.test' and status = 'pending'),
  1,
  'a resend leaves exactly one pending row, not two'
);

select is(
  (select count(*)::int from public.driver_invites
    where email = 'di-recruit@example.test' and status = 'revoked'),
  1,
  'the superseded invite is marked revoked, not deleted'
);

reset role;

-- ===========================================================================
-- driver_invite_lookup: anon-reachable, zero rows for anything wrong
-- ===========================================================================
set local role anon;

select is(
  (select email from public.driver_invite_lookup((select token from di_token2))),
  'di-recruit@example.test',
  'the live token resolves to its locked email, even as anon'
);

select is(
  (select toda_zone_name from public.driver_invite_lookup((select token from di_token2))),
  (select name from di_zone),
  'the same lookup also resolves the correct TODA zone name'
);

select is(
  (select count(*)::int from public.driver_invite_lookup((select token from di_token))),
  0,
  'the superseded (revoked) token resolves to nothing'
);

select is(
  (select count(*)::int from public.driver_invite_lookup(
    '0000000000000000000000000000000000000000000000000000000000000000')),
  0,
  'a token that never existed resolves to nothing, not an error'
);

reset role;

-- ===========================================================================
-- admin_revoke_driver_invite
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078c1';

create temporary table di_token3 as
  select public.admin_create_driver_invite('di-oops@example.test', (select id from di_zone), null) as token;
grant select on di_token3 to authenticated, service_role, anon;

create temporary table di_oops_id as
  select id from public.driver_invites where email = 'di-oops@example.test' and status = 'pending';
grant select on di_oops_id to authenticated, service_role, anon;

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078a1';

select throws_ok(
  $$select public.admin_revoke_driver_invite((select id from di_oops_id))$$,
  '42501', null,
  'a commuter cannot revoke a driver invite'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078c1';

select lives_ok(
  $$select public.admin_revoke_driver_invite((select id from di_oops_id))$$,
  'an LGU admin can revoke a pending driver invite'
);

select is(
  (select status from public.driver_invites where id = (select id from di_oops_id)),
  'revoked',
  'the invite is now revoked'
);

reset role;
set local role anon;

select is(
  (select count(*)::int from public.driver_invite_lookup((select token from di_token3))),
  0,
  'a revoked invite''s token is unreachable'
);

reset role;

-- ===========================================================================
-- driver_finalize_invited_account: reachable only by a trusted server process
-- ===========================================================================
-- Simulates the real order of events: the invite is minted first, while
-- di-recruit@example.test has no account at all (proven above -- creating
-- the invite for that email succeeded, which admin_create_driver_invite
-- would have refused had a profile already existed). Only now does the
-- account get created, mirroring what accept-driver-invite's createUser()
-- call (and handle_new_user()) would have just done for real.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000078a2', 'di-recruit@example.test',
     '{"display_name":"Di Recruit","mobile_number":"+639170007804"}'::jsonb);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000078a2'),
  'commuter',
  'handle_new_user() left the freshly created account as a plain commuter, as always'
);

set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000078c1';

select throws_ok(
  $$select public.driver_finalize_invited_account(
      (select token from di_token2), '00000000-0000-0000-0000-0000000078a2')$$,
  '42501', null,
  'an ordinary authenticated session cannot finalize a driver invite, even an LGU admin'
);

reset role;
set local role service_role;

select throws_ok(
  $$select public.driver_finalize_invited_account(
      (select token from di_token3), '00000000-0000-0000-0000-0000000078a2')$$,
  '42501', null,
  'service_role cannot finalize a revoked invite'
);

select lives_ok(
  $$select public.driver_finalize_invited_account(
      (select token from di_token2), '00000000-0000-0000-0000-0000000078a2')$$,
  'service_role can finalize a valid, pending driver invite'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000078a2'),
  'driver',
  'the accepted account is now a driver'
);

select is(
  (select toda_zone_id from public.driver_profiles where id = '00000000-0000-0000-0000-0000000078a2'),
  (select id from di_zone),
  'the driver_profiles row carries the invite''s own TODA zone'
);

select is(
  (select count(*)::int from public.admin_audit_logs
    where action = 'driver.activate'
      and target_profile_id = '00000000-0000-0000-0000-0000000078a2'),
  1,
  'finalizing wrote exactly one audit row, tagged driver.activate -- the same '
  'tag admin_activate_new_driver() already uses for the other onboarding path'
);

select is(
  (select status from public.driver_invites where email = 'di-recruit@example.test' and status = 'accepted'),
  'accepted',
  'the invite is marked accepted'
);

select throws_ok(
  $$select public.driver_finalize_invited_account(
      (select token from di_token2), '00000000-0000-0000-0000-0000000078a2')$$,
  '42501', null,
  'the same token cannot be accepted twice -- it is no longer pending'
);

reset role;

select * from finish();

rollback;
