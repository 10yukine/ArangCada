-- Preserve dispatch implementation while allowing authenticated admins to ride.
-- Fail closed if the expected guards have changed in another migration.
do $$
declare
  definition text := pg_get_functiondef('public.request_ride(double precision,double precision,double precision,double precision,text,text,text)'::regprocedure);
begin
  if position('v_rider.role <> ''commuter''' in definition) = 0
     or position('v_rider.phone_verified_at is null and not v_rider.is_internal_tester' in definition) = 0 then
    raise exception 'request_ride guards changed; review admin mobile booking migration';
  end if;
  definition := replace(definition,
    'v_rider.role <> ''commuter''', 'v_rider.role not in (''commuter'', ''admin'')');
  definition := replace(definition,
    'v_rider.phone_verified_at is null and not v_rider.is_internal_tester',
    'v_rider.phone_verified_at is null and (v_rider.role = ''admin'' or not v_rider.is_internal_tester)');
  execute definition;
end;
$$;
