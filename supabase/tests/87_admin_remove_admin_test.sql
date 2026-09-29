-- admin_remove_admin (20260929020000): LGU admins offboard other admins.
begin;
select plan(9);

insert into auth.users(id, email, raw_user_meta_data) values
('00000000-0000-0000-0000-000000008701', 'rm-lgu@example.test', '{"display_name":"Rm Lgu","mobile_number":"+639170008701"}'),
('00000000-0000-0000-0000-000000008702', 'rm-lgu2@example.test', '{"display_name":"Rm Lgu Two","mobile_number":"+639170008702"}'),
('00000000-0000-0000-0000-000000008703', 'rm-toda@example.test', '{"display_name":"Rm Toda","mobile_number":"+639170008703"}'),
('00000000-0000-0000-0000-000000008704', 'rm-commuter@example.test', '{"display_name":"Rm Commuter","mobile_number":"+639170008704"}');
update public.profiles set role = 'admin' where id in
  ('00000000-0000-0000-0000-000000008701', '00000000-0000-0000-0000-000000008702', '00000000-0000-0000-0000-000000008703');
insert into public.admin_scopes(admin_id, scope, toda_zone_id)
values ('00000000-0000-0000-0000-000000008703', 'toda', (select id from public.toda_zones where is_active order by code limit 1));
insert into public.admin_invites(email, scope, invited_by, token_hash)
values ('rm-invitee@example.test', 'lgu', '00000000-0000-0000-0000-000000008702', encode(sha256('rm-token'::bytea), 'hex'));

set local role authenticated;

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008703';
select throws_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008702')$$,
  '42501', null, 'a TODA administrator cannot remove administrators');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000008701';
select throws_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008701')$$,
  '22023', null, 'nobody can remove their own admin access');
select throws_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008704')$$,
  '22023', null, 'a non-admin cannot be "removed"');
select lives_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008703')$$,
  'an LGU admin removes a TODA admin');
select lives_ok($$select public.admin_remove_admin('00000000-0000-0000-0000-000000008702')$$,
  'an LGU admin removes another LGU admin');

reset role;
select is((select string_agg(role::text, ',' order by id) from public.profiles
            where id in ('00000000-0000-0000-0000-000000008702', '00000000-0000-0000-0000-000000008703')),
  'commuter,commuter', 'removed admins become ordinary accounts');
select is((select count(*)::int from public.admin_scopes where admin_id = '00000000-0000-0000-0000-000000008703'),
  0, 'the TODA scope is gone');
select is((select status from public.admin_invites where email = 'rm-invitee@example.test'),
  'revoked', 'their pending invites are revoked');

-- Once removed, the person can delete their own account.
set local role service_role;
select lives_ok($$select public.delete_account('00000000-0000-0000-0000-000000008702')$$,
  'a removed admin can then delete their account');

select * from finish();
rollback;
