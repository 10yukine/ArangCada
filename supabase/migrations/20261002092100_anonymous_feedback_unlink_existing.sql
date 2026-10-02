-- Existing anonymous evaluations, made unlinkable the same way as new ones
-- (see 20261002092000).
--
-- This changes stored data and cannot be undone: it deletes the event rows
-- that name the driver of an anonymous response, and rounds those responses'
-- timestamps to the day. Kept in its own file so it can be reviewed, or
-- held back, separately from the function change.
delete from public.trip_events
 where event_type = 'evaluation.driver_feedback_submitted'
   and coalesce((metadata ->> 'anonymous')::boolean, false);

update public.driver_app_feedback
   set submitted_at = date_trunc('day', submitted_at, 'Asia/Manila')
 where is_anonymous
   and submitted_at <> date_trunc('day', submitted_at, 'Asia/Manila');
