-- Dispatch offers a ride only to a driver whose own app reported recently and
-- who holds no live trip (release audit, 2 Oct 2026).
--
-- Two defects shared one cause: is_online was the only thing dispatch read.
--
-- 1. A driver who closed the app without going offline stayed is_online for
--    good. Every nearby booking was offered to them, and each expired offer
--    set them online again (expire_ride), so the next rider got the same absent
--    driver.
-- 2. A heartbeat racing a dispatch could mark a just-assigned driver online
--    again. The next booking nearby picked that driver and failed on
--    trips_one_active_per_driver (23505) instead of looking further.
--
-- last_seen_at is written only by the two functions the driver's own app
-- calls, set_driver_availability and publish_driver_location. Nothing a rider
-- or the clock does (expire_ride, cancel_ride) can make an absent driver look
-- present, so those functions are left alone.
--
-- The functions are patched in place, as 20260926154651 does, so whatever is
-- deployed keeps the rest of its body. Each anchor must occur exactly once or
-- the migration aborts and changes nothing.
--
-- Regression: supabase/tests/90_driver_availability_lifecycle_test.sql.

alter table public.driver_availability
  add column last_seen_at timestamptz not null default now();

comment on column public.driver_availability.last_seen_at is
  'When the driver''s own app last reported (set_driver_availability or '
  'publish_driver_location). Dispatch skips a driver not seen within '
  'dispatch_settings.driver_fresh_seconds.';

-- The idle heartbeat is every 15 s and a GPS fix may take 12 s, so 90 s is
-- several missed beats, not one.
alter table public.dispatch_settings
  add column driver_fresh_seconds integer not null default 90
  constraint dispatch_settings_driver_fresh_seconds_range
    check (driver_fresh_seconds between 30 and 900);

comment on column public.dispatch_settings.driver_fresh_seconds is
  'How recently a driver''s app must have reported for dispatch to offer them '
  'a ride.';

do $$
declare
  v_live constant text :=
    '''requested'', ''searching_driver'', ''driver_assigned'', ''accepted'', '
    '''driver_en_route'', ''arrived'', ''in_progress'', ''emergency_reported''';
  v_scan constant text := 'and availability.longitude is not null';
  v_fresh_and_free constant text := v_scan || '
     and availability.last_seen_at > now() - make_interval(secs => (
           select s.driver_fresh_seconds from public.dispatch_settings s where s.id))
     and not exists (
       select 1 from public.trips live
        where live.driver_id = driver.id
          and live.status in (' || v_live || ')
     )';
  v_patch record;
  v_definition text;
begin
  for v_patch in
    select * from (values
      ('public.request_ride(double precision,double precision,double precision,double precision,text,text,text)',
       v_scan, v_fresh_and_free),
      ('public.retry_dispatch(uuid)', v_scan, v_fresh_and_free),
      -- Take the driver's own row before looking for a live trip. Dispatch
      -- holds that row from its scan until it commits, so a racing heartbeat
      -- waits here, then sees the new trip and is refused.
      ('public.set_driver_availability(boolean,double precision,double precision)',
       'if p_online then',
       'if p_online then
    perform 1 from public.driver_availability
     where driver_id = v_driver.id for update;'),
      ('public.set_driver_availability(boolean,double precision,double precision)',
       'longitude = excluded.longitude,',
       'longitude = excluded.longitude,
         last_seen_at = now(),'),
      ('public.publish_driver_location(uuid,double precision,double precision,double precision)',
       'accuracy_meters = p_accuracy_meters,',
       'accuracy_meters = p_accuracy_meters,
         last_seen_at = now(),'),
      -- The admin console's driver list and live map use the same rule, so an
      -- absent driver is not shown as online there either.
      ('public.admin_list_drivers()',
       'coalesce(a.is_online, false),',
       'coalesce(a.is_online and a.last_seen_at > now() - make_interval(secs => (
           select s.driver_fresh_seconds from public.dispatch_settings s where s.id)), false),')
    ) as patch(func, anchor, replacement)
  loop
    v_definition := pg_get_functiondef(v_patch.func::regprocedure);
    if (length(v_definition) - length(replace(v_definition, v_patch.anchor, '')))
       <> length(v_patch.anchor) then
      raise exception '% changed; review the driver availability lifecycle migration (anchor: %)',
        v_patch.func, v_patch.anchor;
    end if;
    execute replace(v_definition, v_patch.anchor, v_patch.replacement);
  end loop;
end;
$$;

-- Rows the race in (2) already left behind: online while holding a live trip.
update public.driver_availability a
   set is_online = false
 where a.is_online
   and exists (
     select 1 from public.trips t
      where t.driver_id = a.driver_id
        and t.status in (
          'requested', 'searching_driver', 'driver_assigned', 'accepted',
          'driver_en_route', 'arrived', 'in_progress', 'emergency_reported'
        )
   );
