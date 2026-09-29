-- pgTAP: profiles identity columns and the signup trigger.
--
-- WHY THIS FILE EXISTS
--
-- Driver onboarding resolves a person by mobile number or email. Both are
-- therefore authorization-adjacent, and both depend on guarantees that are
-- easy to assume and easy to lose:
--
--   * normalisation -- 0917..., +63917..., and 63917... must collapse to one
--     value, or "does this person already have an account?" silently misses;
--   * uniqueness -- two rows sharing a number make an admin lookup ambiguous
--     at exactly the moment it decides who becomes a driver;
--   * the trigger existing at all -- until 20260825120050 nothing created a
--     profiles row, so public.profiles was empty for every real account and
--     is_admin() could never return true.
--

begin;

select plan(16);

-- ===========================================================================
-- normalize_ph_mobile: every written form of one number collapses to E.164
-- ===========================================================================
select is(
  public.normalize_ph_mobile('+639171234567'), '+639171234567',
  'an already-canonical number is returned unchanged'
);

select is(
  public.normalize_ph_mobile('09171234567'), '+639171234567',
  'the local 09XXXXXXXXX trunk form normalises to E.164'
);

select is(
  public.normalize_ph_mobile('639171234567'), '+639171234567',
  'a number missing only the leading + normalises to E.164'
);

select is(
  public.normalize_ph_mobile('9171234567'), '+639171234567',
  'a bare subscriber number normalises to E.164'
);

select is(
  public.normalize_ph_mobile('0917 123 4567'), '+639171234567',
  'spaces are stripped before matching -- how a number is typed does not matter'
);

select is(
  public.normalize_ph_mobile('(0917) 123-4567'), '+639171234567',
  'punctuation is stripped too'
);

-- ---------------------------------------------------------------------------
-- Non-numbers return null rather than raising: an admin looking up a typo
-- should get "no match", not a failed request.
-- ---------------------------------------------------------------------------
select is(
  public.normalize_ph_mobile('12345'), null,
  'a too-short string is not a PH mobile number and returns null'
);

select is(
  public.normalize_ph_mobile('+14155551234'), null,
  'a non-PH international number returns null rather than being coerced'
);

select is(
  public.normalize_ph_mobile(null), null,
  'null in, null out -- no exception'
);

-- ===========================================================================
-- The signup trigger builds the profiles row
-- ===========================================================================
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000020a1', 'Identity.Test@Example.Test',
     '{"display_name":"Identity Test","mobile_number":"0917 000 0201"}'::jsonb);

select is(
  (select count(*)::int from public.profiles
    where id = '00000000-0000-0000-0000-0000000020a1'),
  1,
  'inserting an auth user creates exactly one profiles row'
);

select is(
  (select phone from public.profiles
    where id = '00000000-0000-0000-0000-0000000020a1'),
  '+639170000201',
  'the trigger normalises the metadata mobile number on the way in'
);

select is(
  (select email from public.profiles
    where id = '00000000-0000-0000-0000-0000000020a1'),
  'identity.test@example.test',
  'email is lowercased, so uniqueness is genuinely case-insensitive'
);

select is(
  (select role::text from public.profiles
    where id = '00000000-0000-0000-0000-0000000020a1'),
  'commuter',
  'every account is born a commuter -- driver role is granted, never self-assigned'
);

-- ---------------------------------------------------------------------------
-- Missing identity fails the signup rather than inventing a placeholder
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-0000-0000-0000000020b2', 'nometa@example.test',
            '{"display_name":"No Phone"}'::jsonb)$$,
  null, null,
  'an auth user with no mobile_number is refused rather than given a placeholder number'
);

select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-0000-0000-0000000020c3', 'noname@example.test',
            '{"mobile_number":"09170000203"}'::jsonb)$$,
  null, null,
  'an auth user with no display_name is refused'
);

-- ===========================================================================
-- Uniqueness: the guarantee the admin lookup depends on
-- ===========================================================================
select throws_ok(
  $$insert into auth.users (id, email, raw_user_meta_data)
    values ('00000000-0000-0000-0000-0000000020d4', 'different@example.test',
            '{"display_name":"Duplicate Number","mobile_number":"+639170000201"}'::jsonb)$$,
  '23505',
  null,
  'a second account cannot take an existing mobile number -- one account per number'
);

select * from finish();

rollback;
