-- Adds complaints and trip_ratings to the supabase_realtime publication
-- (release audit, 2 Oct 2026).
--
-- The admin console listens to eleven tables on one channel
-- (supabase_admin_repository.dart, subscribe()). These two have been in that
-- list since 6 Sep 2026 but were never published. Realtime refuses the whole
-- channel when one of its tables is not published ("Unable to subscribe to
-- changes with given parameters"), so the console received no live changes at
-- all: no new-SOS alert, no new trip, no document upload, until a reload.
--
-- Both tables keep their RLS: a row change reaches only its author or an
-- administrator scoped to that TODA.
--
-- Same idempotent shape as 20260909020000. Check after applying: the probe in
-- the audit's evidence folder must report "Subscribed to PostgreSQL" for the
-- console's list.
do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array[
      'complaints',
      'trip_ratings'
    ]
    loop
      if not exists (
        select 1
          from pg_publication_tables
         where pubname = 'supabase_realtime'
           and schemaname = 'public'
           and tablename = v_table
      ) then
        execute format(
          'alter publication supabase_realtime add table public.%I',
          v_table
        );
      end if;
    end loop;
  end if;
end;
$$;
