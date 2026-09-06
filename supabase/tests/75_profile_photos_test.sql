-- pgTAP: profile photos -- Storage RLS on the profile-photos bucket, and
-- the direct client update of profiles.avatar_path (no RPC; the security
-- boundary is Storage's own RLS, see the migration's header comment).
--
-- See .pipeline/specs.md Spec 15. Fixture/style follows
-- 74_fare_class_claims_test.sql.

begin;

select plan(12);

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000075a1', 'pfp-owner@example.test',
   '{"display_name":"PFP Owner","mobile_number":"+639170007501"}'::jsonb),
  ('00000000-0000-0000-0000-0000000075c1', 'pfp-admin@example.test',
   '{"display_name":"PFP Admin","mobile_number":"+639170007502"}'::jsonb),
  ('00000000-0000-0000-0000-0000000075d1', 'pfp-stranger@example.test',
   '{"display_name":"PFP Stranger","mobile_number":"+639170007503"}'::jsonb);

insert into public.profiles (id, role, display_name, phone, email, status) values
  ('00000000-0000-0000-0000-0000000075a1', 'commuter', 'PFP Owner',
   '+639170007501', 'pfp-owner@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000075c1', 'admin',    'PFP Admin',
   '+639170007502', 'pfp-admin@example.test',    'active'),
  ('00000000-0000-0000-0000-0000000075d1', 'commuter', 'PFP Stranger',
   '+639170007503', 'pfp-stranger@example.test', 'active')
on conflict (id) do update
  set role = excluded.role, status = excluded.status, phone = excluded.phone;

-- ---------------------------------------------------------------------------
-- Storage RLS: own-folder write/read, admin read, stranger denied
-- ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'profile-photos',
      '00000000-0000-0000-0000-0000000075a1/photo.jpg',
      '00000000-0000-0000-0000-0000000075a1')$$,
  'a commuter can upload under their own auth.uid() folder'
);

select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner) values (
      'profile-photos',
      '00000000-0000-0000-0000-0000000075d1/sneaky.jpg',
      '00000000-0000-0000-0000-0000000075a1')$$,
  '42501', null,
  'SECURITY: a commuter cannot upload into someone else''s folder'
);

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  1,
  'the owner can select their own uploaded photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075d1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  0,
  'SECURITY: a stranger cannot select another commuter''s photo'
);

set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075c1';

select is(
  (select count(*)::integer from storage.objects
    where name = '00000000-0000-0000-0000-0000000075a1/photo.jpg'),
  1,
  'an admin CAN select a commuter''s uploaded photo'
);

-- ---------------------------------------------------------------------------
-- profiles.avatar_path -- direct client update, no RPC
-- ---------------------------------------------------------------------------
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select lives_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075a1/photo.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'a commuter can point their own avatar_path at their own uploaded photo'
);

select is(
  (select avatar_path from public.profiles
    where id = '00000000-0000-0000-0000-0000000075a1'),
  '00000000-0000-0000-0000-0000000075a1/photo.jpg',
  'the update actually took'
);

select throws_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075d1/sneaky.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  '23514', null,
  'SECURITY: avatar_path must stay prefixed with the row''s own id, even on '
  'a direct client update with no RPC to check it'
);

-- A stranger's UPDATE naming someone else's row is not a privilege escalation
-- risk here (Storage RLS is the real gate either way), but profiles_update_own
-- should still mean it simply matches zero rows rather than succeeding.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075d1';

select lives_ok(
  $$update public.profiles
       set avatar_path = '00000000-0000-0000-0000-0000000075d1/photo.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'SECURITY: a stranger targeting someone else''s row by id does not error, '
  'it just matches nothing'
);

-- Switch back to the owner before reading -- profiles_select_own means
-- 075d1 cannot see 075a1's row at all, which would make the next assertion
-- read NULL for the wrong reason (invisible, not unchanged). Same lesson
-- as 74_fare_class_claims_test.sql's `reset role`/identity-switch fix.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000075a1';

select is(
  (select avatar_path from public.profiles
    where id = '00000000-0000-0000-0000-0000000075a1'),
  '00000000-0000-0000-0000-0000000075a1/photo.jpg',
  'SECURITY: ...and the owner''s avatar_path is unchanged by that attempt'
);

-- Composes with the existing display_name/phone grant rather than
-- replacing it -- both columns settable in the same statement.

select lives_ok(
  $$update public.profiles
       set display_name = 'PFP Owner Renamed',
           avatar_path = '00000000-0000-0000-0000-0000000075a1/photo2.jpg'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  'the new avatar_path grant composes with the existing display_name grant '
  'in a single statement'
);

select throws_ok(
  $$update public.profiles
       set role = 'admin'
     where id = '00000000-0000-0000-0000-0000000075a1'$$,
  '42501', null,
  'guard_profiles_privileged_columns() still blocks role, unaffected by the '
  'new avatar_path grant'
);

select * from finish();

rollback;
