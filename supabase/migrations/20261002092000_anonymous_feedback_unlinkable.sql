-- An anonymous app evaluation must not be attributable by an administrator
-- (release audit, 2 Oct 2026).
--
-- driver_app_feedback deliberately has no driver or trip column, and the
-- driver is told "Hindi ipapakita ang iyong pangalan". But
-- submit_driver_feedback also wrote a trip_events row naming the driver and
-- the trip, in the same transaction, so its created_at was identical to the
-- response's submitted_at. An admin who can read both tables (any LGU admin,
-- or the TODA admin of that zone) could join them on the timestamp and put a
-- name on every anonymous response and its comment.
--
-- For an anonymous submission the function now writes no event, and stores
-- the day (Manila time) instead of the instant. Named submissions are
-- unchanged. Existing rows are handled by the next migration.
--
-- Not closed here: an admin watching responses arrive over Realtime can still
-- guess from which trip just ended. Only aggregate-only access would stop
-- that.
--
-- Regression: supabase/tests/60_live_connected_vertical_slice_test.sql.
create or replace function public.submit_driver_feedback(
  p_trip_id uuid,
  p_answers jsonb,
  p_comment text,
  p_anonymous boolean
)
returns public.driver_app_feedback
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pending public.driver_feedback_obligations%rowtype;
  v_response public.driver_app_feedback%rowtype;
  v_name text;
begin
  select * into v_pending
    from public.driver_feedback_obligations
   where trip_id = p_trip_id
   for update;

  if not found or v_pending.driver_id <> auth.uid() then
    raise exception 'only the assigned driver may answer this app evaluation'
      using errcode = '42501';
  end if;

  if v_pending.response_id is not null then
    select * into v_response from public.driver_app_feedback
     where id = v_pending.response_id;
    return v_response;
  end if;

  if not coalesce(public.driver_feedback_answers_valid(p_answers), false) then
    raise exception 'all seven app-evaluation answers must use the 1-5 Likert scale'
      using errcode = '22023';
  end if;

  if p_comment is not null and char_length(p_comment) > 1000 then
    raise exception 'optional driver comments cannot exceed 1000 characters'
      using errcode = '22023';
  end if;

  if p_anonymous is null then
    raise exception 'the driver must explicitly choose the anonymity setting'
      using errcode = '22023';
  end if;

  if not p_anonymous then
    select display_name into v_name from public.profiles where id = auth.uid();
  end if;

  insert into public.driver_app_feedback (
    toda_zone_id, answers, comment, is_anonymous, driver_display_name, submitted_at
  )
  values (
    v_pending.toda_zone_id,
    p_answers,
    nullif(trim(coalesce(p_comment, '')), ''),
    p_anonymous,
    v_name,
    case when p_anonymous
         then date_trunc('day', now(), 'Asia/Manila')
         else now() end
  )
  returning * into v_response;

  -- Readable by the driver only, so it keeps the real time.
  update public.driver_feedback_obligations
     set response_id = v_response.id, submitted_at = now()
   where trip_id = p_trip_id;

  if not p_anonymous then
    insert into public.trip_events (trip_id, actor_id, event_type, metadata)
    values (
      p_trip_id,
      auth.uid(),
      'evaluation.driver_feedback_submitted',
      jsonb_build_object('anonymous', false)
    );
  end if;

  return v_response;
end;
$$;
