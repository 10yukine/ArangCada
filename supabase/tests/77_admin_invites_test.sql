-- pgTAP: LGU/TODA admin invites (Spec 19).
--
-- WHY THIS FILE EXISTS
--
-- admin_finalize_invited_account() is the only place a profiles row ever
-- gets role = 'admin' from outside a pre-seeded fixture, and it runs as
-- service_role with no auth.uid() of its own -- the exact shape that made
-- admin_activate_new_driver() worth testing on its own (55_driver_onboarding
-- _test.sql). The invite token itself is the other half: it must resolve for
-- the right token and refuse silently (zero rows, not an error) for every
-- wrong one, and it must never be reachable a second time once accepted or
-- revoked.

begin;

select plan(30);

-- ---------------------------------------------------------------------------
-- Fixtures. Synthetic uuids and example.test addresses only (CLAUDE.md rule 10).
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000077c1', 'ai-lgu@example.test',
     '{"display_name":"Ai Lgu","mobile_number":"+639170007701"}'::jsonb),
  ('00000000-0000-0000-0000-0000000077c2', 'ai-toda@example.test',
     '{"display_name":"Ai Toda","mobile_number":"+639170007702"}'::jsonb),
  ('00000000-0000-0000-0000-0000000077a1', 'ai-commuter@example.test',
     '{"display_name":"Ai Commuter","mobile_number":"+639170007703"}'::jsonb),
  ('00000000-0000-0000-0000-0000000077a2', 'ai-newadmin@example.test',
     '{"display_name":"New Admin","mobile_number":"+639170007704"}'::jsonb);

update public.profiles set role = 'admin' where id in (
  '00000000-0000-0000-0000-0000000077c1', '00000000-0000-0000-0000-0000000077c2'
);

create temporary table ai_zone as
  select id from public.toda_zones order by code limit 1;
grant select on ai_zone to authenticated, service_role;

insert into public.admin_scopes (admin_id, scope, toda_zone_id)
values ('00000000-0000-0000-0000-0000000077c2', 'toda', (select id from ai_zone));

-- Stands in for what handle_new_user() would already have created for a real
-- invited-admin signup before the Edge Function calls
-- admin_finalize_invited_account() -- that function never creates the
-- profile row itself, only promotes an existing one.
update public.profiles set role = 'commuter'
 where id = '00000000-0000-0000-0000-0000000077a2';

-- ===========================================================================
-- handle_new_user(): invited_admin exempts the phone requirement
-- ===========================================================================
select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-0000-0000-0000000077e1', 'ai-nophone@example.test',
            '{"display_name":"No Phone"}'::jsonb)$$,
  '23514', null,
  'a plain signup with no phone still fails, unchanged by this migration'
);

select lives_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-0000-0000-0000000077e2', 'ai-invited@example.test',
            '{"display_name":"Invited Admin","invited_admin":true}'::jsonb)$$,
  'an invited_admin account is exempt from the phone requirement -- the flag '
  'lives in raw_user_meta_data, confirmed present at insert time against the '
  'hosted project (raw_app_meta_data is not, see 20260908030000)'
);

select is(
  (select phone from public.profiles where id = '00000000-0000-0000-0000-0000000077e2'),
  null,
  'its phone column is left null rather than a fabricated placeholder'
);

-- ===========================================================================
-- admin_create_invite
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077a1';

select throws_ok(
  $$select public.admin_create_invite('someone@example.test', 'lgu', null)$$,
  '42501', null,
  'a commuter cannot send an admin invite'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077c2';

select throws_ok(
  $$select public.admin_create_invite('someone@example.test', 'lgu', null)$$,
  '42501', null,
  'a TODA-scoped admin cannot send an admin invite -- LGU only'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077c1';

select throws_ok(
  $$select public.admin_create_invite('not-an-email', 'lgu', null)$$,
  '22023', null,
  'a malformed email is rejected'
);

select throws_ok(
  $$select public.admin_create_invite('someone@example.test', 'lgu', (select id from ai_zone))$$,
  '22023', null,
  'an lgu invite must not carry a toda zone'
);

select throws_ok(
  $$select public.admin_create_invite('someone@example.test', 'toda', null)$$,
  '22023', null,
  'a toda invite requires a toda zone'
);

select throws_ok(
  $$select public.admin_create_invite('ai-lgu@example.test', 'lgu', null)$$,
  '23505', null,
  'an email already belonging to an active admin is refused'
);

create temporary table ai_token as
  select public.admin_create_invite('ai-recruit@example.test', 'toda', (select id from ai_zone)) as token;
grant select on ai_token to authenticated, service_role, anon;

select is(
  (select char_length(token) from ai_token), 64,
  'the returned raw token is 64 hex characters'
);

select is(
  (select count(*)::int from public.admin_invites
    where email = 'ai-recruit@example.test' and status = 'pending' and scope = 'toda'),
  1,
  'exactly one pending invite row was written'
);

select isnt(
  (select token_hash from public.admin_invites where email = 'ai-recruit@example.test'),
  (select token from ai_token),
  'the stored hash is not the raw token -- it is never kept in plaintext'
);

select is(
  (select count(*)::int from public.admin_audit_logs where action = 'admin_invite.created'),
  1,
  'invite creation wrote exactly one audit row'
);

-- Re-inviting the same email supersedes the first pending row.
create temporary table ai_token2 as
  select public.admin_create_invite('ai-recruit@example.test', 'toda', (select id from ai_zone)) as token;
grant select on ai_token2 to authenticated, service_role, anon;

select is(
  (select count(*)::int from public.admin_invites
    where email = 'ai-recruit@example.test' and status = 'pending'),
  1,
  'a resend leaves exactly one pending row, not two'
);

select is(
  (select count(*)::int from public.admin_invites
    where email = 'ai-recruit@example.test' and status = 'revoked'),
  1,
  'the superseded invite is marked revoked, not deleted'
);

reset role;

-- ===========================================================================
-- admin_invite_lookup: anon-reachable, zero rows for anything wrong
-- ===========================================================================
set local role anon;

select is(
  (select email from public.admin_invite_lookup((select token from ai_token2))),
  'ai-recruit@example.test',
  'the live token resolves to its locked email, even as anon'
);

select is(
  (select count(*)::int from public.admin_invite_lookup((select token from ai_token))),
  0,
  'the superseded (revoked) token resolves to nothing'
);

select is(
  (select count(*)::int from public.admin_invite_lookup(
    '0000000000000000000000000000000000000000000000000000000000000000')),
  0,
  'a token that never existed resolves to nothing, not an error'
);

reset role;

-- ===========================================================================
-- admin_revoke_invite
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077c1';

create temporary table ai_token3 as
  select public.admin_create_invite('ai-oops@example.test', 'lgu', null) as token;
grant select on ai_token3 to authenticated, service_role, anon;

create temporary table ai_oops_id as
  select id from public.admin_invites where email = 'ai-oops@example.test' and status = 'pending';
grant select on ai_oops_id to authenticated, service_role, anon;

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077a1';

select throws_ok(
  $$select public.admin_revoke_invite((select id from ai_oops_id))$$,
  '42501', null,
  'a commuter cannot revoke an invite'
);

reset role;
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077c1';

select lives_ok(
  $$select public.admin_revoke_invite((select id from ai_oops_id))$$,
  'an LGU admin can revoke their own pending invite'
);

select is(
  (select status from public.admin_invites where id = (select id from ai_oops_id)),
  'revoked',
  'the invite is now revoked'
);

reset role;
set local role anon;

select is(
  (select count(*)::int from public.admin_invite_lookup((select token from ai_token3))),
  0,
  'a revoked invite''s token is unreachable'
);

reset role;

-- ===========================================================================
-- admin_finalize_invited_account: reachable only by a trusted server process
-- ===========================================================================
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000077c1';

select throws_ok(
  $$select public.admin_finalize_invited_account(
      (select token from ai_token2), '00000000-0000-0000-0000-0000000077a2', 'New', 'Admin')$$,
  '42501', null,
  'an ordinary authenticated session cannot finalize an invite, even an LGU admin'
);

reset role;
set local role service_role;

select throws_ok(
  $$select public.admin_finalize_invited_account(
      (select token from ai_token3), '00000000-0000-0000-0000-0000000077a2', 'New', 'Admin')$$,
  '42501', null,
  'service_role cannot finalize a revoked invite'
);

select lives_ok(
  $$select public.admin_finalize_invited_account(
      (select token from ai_token2), '00000000-0000-0000-0000-0000000077a2', 'New', 'Admin')$$,
  'service_role can finalize a valid, pending invite'
);

select is(
  (select role::text from public.profiles where id = '00000000-0000-0000-0000-0000000077a2'),
  'admin',
  'the accepted account is now an admin'
);

select is(
  (select scope from public.admin_scopes where admin_id = '00000000-0000-0000-0000-0000000077a2'),
  'toda',
  'a toda-scope invite wrote a matching admin_scopes row'
);

select is(
  (select last_name from public.profiles where id = '00000000-0000-0000-0000-0000000077a2'),
  'Admin',
  'first/last name were recorded on the profile'
);

select is(
  (select count(*)::int from public.admin_audit_logs
    where action = 'admin_invite.accepted'
      and target_profile_id = '00000000-0000-0000-0000-0000000077a2'
      and actor_id = '00000000-0000-0000-0000-0000000077c1'),
  1,
  'acceptance wrote exactly one audit row, attributed to the inviting LGU admin'
);

select throws_ok(
  $$select public.admin_finalize_invited_account(
      (select token from ai_token2), '00000000-0000-0000-0000-0000000077a2', 'New', 'Admin')$$,
  '42501', null,
  'the same token cannot be accepted twice -- it is no longer pending'
);

reset role;

select * from finish();

rollback;
