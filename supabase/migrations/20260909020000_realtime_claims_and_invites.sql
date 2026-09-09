-- Adds fare_class_claims and driver_invites to the supabase_realtime
-- publication.
--
-- Owner report, 9 Sep 2026: a submitted discount claim needed a manual
-- admin_web page reload to appear at all (a separate bug -- refresh() never
-- wired fareClassClaims into state, fixed the same pass in
-- admin_controller.dart), and a driver's enrolled status needed a reload
-- too. driver_profiles was already in this publication; fare_class_claims
-- and driver_invites never were, so admin_web's existing subscribe()
-- mechanism (see supabase_admin_repository.dart) had nothing to listen for
-- on either table.
--
-- Same idempotent shape as every prior addition to this publication --
-- see 20260825133421_live_connected_vertical_slice.sql and
-- 20260825170000_live_connected_remote_reconciliation.sql.
do $$
declare
  v_table text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach v_table in array array[
      'fare_class_claims',
      'driver_invites'
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
