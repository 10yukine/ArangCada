-- The in-app driver evaluation is withdrawn (owner, 16 Nov 2026). The capstone
-- evaluation now uses printed questionnaires outside the app, so the app no
-- longer asks drivers for a survey after a trip and no longer holds them
-- offline until they answer one.
--
-- Now:
--   * complete_trip records no evaluation obligation.
--   * Obligations nobody answered are deleted, so no driver stays blocked from
--     going online or from dispatch by a survey that can no longer be opened.
--   * submit_driver_feedback is dropped: nothing can owe a response any more.
--
-- Kept on purpose:
--   * driver_app_feedback and the answered obligations: the responses already
--     collected stay as they are, readable under their existing policies.
--   * get_driver_feedback_state, driver_feedback_obligations and its read
--     policy: mobile build 4059 calls them when a driver signs in. With no
--     pending obligation the answer is always "nothing pending".
--   * get_feedback_summary, get_feedback_settings, update_feedback_settings:
--     the administration console deployed before this change loads them.
--   * The "pending obligation" checks inside set_driver_availability and the
--     dispatch functions: they can never be true again.
--
-- ponytail: the kept functions, checks and app_evaluation_settings are dead
-- weight. Drop them in a later migration once min_mobile_build is above 4059
-- and the console without its Evaluation section is deployed.
--
-- complete_trip is patched in place, as 20261014100000 does.
-- Each anchor must occur exactly once or the migration aborts and changes
-- nothing.
--
-- Regression: supabase/tests/60_live_connected_vertical_slice_test.sql

do $$
declare
  v_definition text := pg_get_functiondef('public.complete_trip(uuid)'::regprocedure);
  -- The evaluation block runs from the settings read to the end of the
  -- obligation insert. It is cut by position, so the patch does not depend on
  -- the exact text between the two anchors.
  v_start_anchor text := 'select * into v_settings from public.app_evaluation_settings where id;';
  v_end_anchor text := 'on conflict (trip_id) do nothing;';
  v_start integer;
  v_end integer;
  v_anchor text;
begin
  foreach v_anchor in array array[
    v_start_anchor,
    v_end_anchor,
    'v_settings public.app_evaluation_settings%rowtype;',
    'v_completed integer;',
    'v_due boolean;',
    'jsonb_build_object(''feedback_due'', v_due)'
  ] loop
    if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
       <> length(v_anchor) then
      raise exception 'complete_trip changed; review this migration (anchor: %)', v_anchor;
    end if;
  end loop;

  v_start := strpos(v_definition, v_start_anchor);
  v_end := strpos(v_definition, v_end_anchor);
  -- The insert sits inside "if v_due then ... end if;", which closes right
  -- after the end anchor.
  v_end := v_end + strpos(substr(v_definition, v_end), 'end if;') + length('end if;') - 1;
  if v_start = 0 or v_end <= v_start then
    raise exception 'complete_trip changed; the evaluation block was not found';
  end if;
  v_definition := substr(v_definition, 1, v_start - 1) || substr(v_definition, v_end);

  v_definition := replace(v_definition, 'v_settings public.app_evaluation_settings%rowtype;', '');
  v_definition := replace(v_definition, 'v_completed integer;', '');
  v_definition := replace(v_definition, 'v_due boolean;', '');
  v_definition := replace(v_definition,
    'jsonb_build_object(''feedback_due'', v_due)', '''{}''::jsonb');

  if v_definition ~ 'v_settings|v_completed|v_due|feedback' then
    raise exception 'complete_trip still refers to the evaluation after the patch';
  end if;
  execute v_definition;
end;
$$;

delete from public.driver_feedback_obligations where submitted_at is null;

drop function public.submit_driver_feedback(uuid, jsonb, text, boolean);
