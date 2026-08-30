-- PUBLIC includes anon. Keep these RPCs available to signed-in clients while
-- preventing unauthenticated PostgREST execution.
do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
  loop
    execute format('revoke execute on function %s from public', f.signature);
    execute format('grant execute on function %s to authenticated', f.signature);
  end loop;
end
$$;
