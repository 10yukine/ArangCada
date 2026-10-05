-- 20261005090000: each verified account has a daily place-search budget, and
-- nobody else can search or read the counts.
begin;
select plan(10);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000096a1', 'ps-verified@example.test',
   '{"display_name":"PS Verified","mobile_number":"+639170009601"}'::jsonb),
  ('00000000-0000-0000-0000-0000000096a2', 'ps-other@example.test',
   '{"display_name":"PS Other","mobile_number":"+639170009602"}'::jsonb),
  ('00000000-0000-0000-0000-0000000096a3', 'ps-unverified@example.test',
   '{"display_name":"PS Unverified","mobile_number":"+639170009603"}'::jsonb);

update public.profiles set phone_verified_at = now()
 where id in ('00000000-0000-0000-0000-0000000096a1',
              '00000000-0000-0000-0000-0000000096a2');

-- An account that never verified gets no search and leaves no count.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000096a3';
select is(public.consume_place_search(), false,
  'an unverified account cannot search');
reset role;
select is(
  (select count(*)::int from public.place_search_usage
    where user_id = '00000000-0000-0000-0000-0000000096a3'),
  0, 'and nothing is counted for it');

-- A verified account searches, and each search is counted.
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000096a1';
select is(public.consume_place_search(), true, 'a verified account can search');
select is(public.consume_place_search(), true, 'and again');
reset role;
select is(
  (select requests from public.place_search_usage
    where user_id = '00000000-0000-0000-0000-0000000096a1' and day = current_date),
  2, 'two searches are counted');

-- The 300th search is the last one that day.
update public.place_search_usage set requests = 299
 where user_id = '00000000-0000-0000-0000-0000000096a1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000096a1';
select is(public.consume_place_search(), true, 'the 300th search is allowed');
select is(public.consume_place_search(), false, 'the 301st is refused');

-- One account's use does not touch another's.
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000096a2';
select is(public.consume_place_search(), true,
  'another account still has its own budget');

-- The counts are not readable through the API.
select throws_ok(
  $$select * from public.place_search_usage$$,
  '42501', null, 'a signed-in user cannot read the counts');
reset role;

-- Without a session there is no search at all.
set local role anon;
select throws_ok(
  $$select public.consume_place_search()$$,
  '42501', null, 'an anonymous caller cannot search');
reset role;

select * from finish();
rollback;
