-- A waiting driver may be anywhere in the service area, not only inside the
-- boundary of the TODA they belong to.
--
-- Calamba City Hall withdrew TODA-jurisdiction dispatch on 31 Aug 2026, and
-- the LGU administrator confirmed it in October: a booking goes to the nearest
-- eligible driver in Calamba, whatever their TODA. request_ride and
-- retry_dispatch have matched by distance since 20260831090000, but
-- set_driver_availability still refused a driver located outside their own
-- TODA's polygon. The app calls it every 15 seconds while a driver waits, so a
-- driver who crossed that line stopped being reported, went stale after
-- driver_fresh_seconds and was no longer offered rides.
--
-- With one city-wide zone, as hosted has today, the two rules give the same
-- answer. They part as soon as a second TODA has its own boundary.
--
-- "Service area" here is the union of the active zones. It is Calamba only
-- while that union is the city's verified boundary. Splitting it into TODA
-- polygons later does not keep that true by itself: the union has to be
-- checked against the city boundary whenever a zone is added or changed.
--
-- Now the driver has to be inside the service area: any active zone, where a
-- developer-test zone counts only for a developer-test identity. Unchanged:
-- approval, documents and suspension (can_driver_go_online), pending feedback,
-- one live trip per driver, the freshness window, and the driver's own TODA
-- having to be active. Pickup and destination checks, fares and the recorded
-- pickup TODA are not touched.
--
-- Patched in place, as 20261002130000 does. Each anchor must occur exactly
-- once or the migration aborts and changes nothing.
--
-- Regression: supabase/tests/95_drivers_online_anywhere_in_calamba_test.sql
do $$
declare
  v_patch record;
  v_definition text :=
    pg_get_functiondef(
      'public.set_driver_availability(boolean,double precision,double precision)'::regprocedure);
begin
  for v_patch in
    select * from (values
      ('not public.is_point_in_toda_zone(v_driver.toda_zone_id, p_lng, p_lat)',
       'not coalesce(v_zone.is_active, false)
       or not exists (
         select 1 from public.toda_zones z
          where z.is_active
            and (v_profile.is_internal_tester or not z.is_internal_test)
            and public.st_covers(
                  z.boundary,
                  public.st_setsrid(public.st_makepoint(p_lng, p_lat), 4326))
       )'),
      ('an online driver must be located inside the assigned TODA',
       'an online driver must be inside the Calamba service area and belong to an active TODA')
    ) as patch(anchor, replacement)
  loop
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception 'set_driver_availability changed; review this migration (anchor: %)',
        v_patch.anchor;
    end if;
    v_definition := replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
  execute v_definition;
end;
$$;
