-- Server-side bounds for three inputs that had none (release audit, 2 Oct 2026).
--
-- 1. Names. profiles.display_name, first_name and last_name took a string of
--    any length, or only spaces, from signup metadata, the invite forms and
--    the name edits. They are shown to drivers, riders and administrators and
--    copied onto every trip. NOT VALID: rows already stored are left alone,
--    every insert and update from now on is checked.
alter table public.profiles
  add constraint profiles_names_bounded check (
    char_length(btrim(display_name)) between 1 and 120
    and (first_name is null or char_length(btrim(first_name)) between 1 and 60)
    and (last_name is null or char_length(btrim(last_name)) between 1 and 60)
  ) not valid;

-- 2. GPS accuracy. "p_accuracy_meters < 0" lets NaN and Infinity through
--    (NaN sorts above every number), and the value is stored and shown. Patched
--    in place, as 20260926154651 does; the anchor must occur exactly once.
do $$
declare
  v_anchor constant text := '(p_accuracy_meters is not null and p_accuracy_meters < 0)';
  v_func regprocedure;
  v_definition text;
begin
  foreach v_func in array array[
    'public.publish_driver_location(uuid,double precision,double precision,double precision)'::regprocedure,
    'public.create_sos_report(uuid,text,double precision,double precision,double precision,text)'::regprocedure
  ] loop
    v_definition := pg_get_functiondef(v_func);
    if (length(v_definition) - length(replace(v_definition, v_anchor, '')))
       <> length(v_anchor) then
      raise exception '% changed; review the input bounds migration', v_func;
    end if;
    execute replace(v_definition, v_anchor,
      '(p_accuracy_meters is not null
          and not (p_accuracy_meters >= 0 and p_accuracy_meters < 100000))');
  end loop;
end;
$$;
