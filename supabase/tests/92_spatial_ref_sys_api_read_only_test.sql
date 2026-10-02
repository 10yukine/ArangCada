-- 20261002120000: API callers cannot change public.spatial_ref_sys.
begin;
select plan(11);

-- The hosted project's state: RLS is off (20260830130000 could not enable it),
-- the table's owner granted these and the migration role cannot take them
-- back. The trigger has to hold on its own.
alter table public.spatial_ref_sys disable row level security;
grant insert, update, delete, truncate on public.spatial_ref_sys to anon, authenticated;

set local role anon;
select throws_ok($$ insert into public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text)
                    values (990001, 'test', 990001, 'x', 'x') $$,
  '42501', 'spatial_ref_sys is read-only', 'anon cannot add an SRID');
select throws_ok($$ update public.spatial_ref_sys set proj4text = 'x' where srid = 4326 $$,
  '42501', 'spatial_ref_sys is read-only', 'anon cannot rewrite an SRID');
select throws_ok($$ delete from public.spatial_ref_sys where srid = 4326 $$,
  '42501', 'spatial_ref_sys is read-only', 'anon cannot delete an SRID');
select throws_ok($$ truncate public.spatial_ref_sys $$,
  '42501', 'spatial_ref_sys is read-only', 'anon cannot empty the table');
select is((select count(*) from public.spatial_ref_sys where srid = 4326), 1::bigint,
  'anon can still read the table');
reset role;

set local role authenticated;
select throws_ok($$ update public.spatial_ref_sys set proj4text = 'x' where srid = 4326 $$,
  '42501', 'spatial_ref_sys is read-only', 'a signed-in user cannot rewrite an SRID');
select throws_ok($$ delete from public.spatial_ref_sys $$,
  '42501', 'spatial_ref_sys is read-only', 'a signed-in user cannot delete SRIDs');
select throws_ok($$ truncate public.spatial_ref_sys $$,
  '42501', 'spatial_ref_sys is read-only', 'a signed-in user cannot empty the table');
select is(round(st_distance(st_point(121.16, 14.21)::geography, st_point(121.17, 14.21)::geography)), 1079::double precision,
  'distances still compute for a signed-in user');
reset role;

select lives_ok($$ update public.spatial_ref_sys set proj4text = proj4text where srid = 4326 $$,
  'the table can still be maintained by other roles');
select ok(not has_function_privilege('anon', 'public.spatial_ref_sys_api_read_only()', 'execute'),
  'the trigger function is not an RPC');

select * from finish();
rollback;
