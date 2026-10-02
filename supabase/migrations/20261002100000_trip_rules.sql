-- Three trip rules decided after the release audit (2 Oct 2026).
--
-- 1. Suspension. Suspending a driver only changed profiles.status. A driver
--    suspended for misconduct could still go on to the pickup and start the
--    trip, and the rider was never told. Now:
--      * the driver is taken offline;
--      * an offer they had not answered is closed like an expired offer, and a
--        ride they had accepted but not started is cancelled, so the rider is
--        released and can book again (reason 'driver_suspended', so the admin
--        console does not count it as the driver's own cancellation);
--      * a trip already in progress is left to finish, because the passenger
--        is on board;
--      * mark_arrived and start_trip refuse a suspended driver, in case a
--        suspension and an accept cross.
--
-- 2. A rider could cancel a trip that had already started, by calling
--    cancel_ride directly (the app offers no such button). That left no fare
--    record and put the driver back online with the passenger still on board.
--    A started trip ends when it is completed; the driver can do that anywhere.
--
-- 3. publish_driver_location updated the driver's availability row and then
--    the trip, while complete_trip takes the trip and then the availability
--    row. When the first location fix inside the drop-off radius met the
--    Complete tap, one of the two was rolled back as a deadlock, usually the
--    completion. publish_driver_location now takes the trip first, like every
--    other function.
--
-- Patched in place, as 20260926154651 does. Each anchor must occur exactly
-- once or the migration aborts and changes nothing.
--
-- Regression: supabase/tests/91_trip_rules_test.sql; the deadlock needs two
-- sessions and is covered by the audit's concurrency harness.
do $$
declare
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.admin_set_profile_status(uuid,public.profile_status,text)',
       'insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)',
       'if p_status = ''suspended'' then
    with released as (
      update public.trips
         set status = ''no_driver_available'', updated_at = now()
       where driver_id = p_profile_id and status = ''driver_assigned''
      returning id
    )
    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    select id, v_actor, ''ride.expired'', jsonb_build_object(''reason'', ''driver_suspended'')
      from released;

    with cancelled as (
      update public.trips
         set status = ''cancelled_by_driver'',
             cancellation_reason = ''driver_suspended'',
             updated_at = now()
       where driver_id = p_profile_id
         and status in (''accepted'', ''driver_en_route'', ''arrived'')
      returning id
    )
    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    select id, v_actor, ''ride.cancelled_by_driver'',
           jsonb_build_object(''reason'', ''driver_suspended'')
      from cancelled;

    -- After the trips, the order every other function takes these two in.
    update public.driver_availability
       set is_online = false
     where driver_id = p_profile_id and is_online;
  end if;

  insert into public.admin_audit_logs (actor_id, action, target_profile_id, reason)'),
      ('public.mark_arrived(uuid)',
       'if v_trip.status = ''arrived'' then',
       'if not exists (
    select 1 from public.profiles p
     where p.id = v_trip.driver_id and p.status = ''active''
  ) then
    raise exception ''this driver account is suspended''
      using errcode = ''42501'';
  end if;
  if v_trip.status = ''arrived'' then'),
      ('public.start_trip(uuid)',
       'if v_trip.status = ''in_progress'' then',
       'if not exists (
    select 1 from public.profiles p
     where p.id = v_trip.driver_id and p.status = ''active''
  ) then
    raise exception ''this driver account is suspended''
      using errcode = ''42501'';
  end if;
  if v_trip.status = ''in_progress'' then'),
      ('public.cancel_ride(uuid)',
       'if v_trip.status in (''completed'', ''cancelled_by_rider'', ''cancelled_by_driver'', ''no_driver_available'') then',
       'if v_trip.status = ''in_progress'' then
    raise exception ''a trip that has started cannot be cancelled; ask the driver to end it''
      using errcode = ''22023'';
  end if;

  if v_trip.status in (''completed'', ''cancelled_by_rider'', ''cancelled_by_driver'', ''no_driver_available'') then'),
      ('public.publish_driver_location(uuid,double precision,double precision,double precision)',
       'select * into v_trip from public.trips where id = p_trip_id;',
       'select * into v_trip from public.trips where id = p_trip_id for no key update;')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the trip rules migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;
