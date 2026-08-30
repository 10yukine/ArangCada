create or replace function public.trips_fcm_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_id bigint;
  webhook_url text;
  payload jsonb;
begin
  -- Skip if status hasn't changed to driver_assigned
  if tg_op = 'UPDATE' and old.status = new.status then
    return new;
  end if;

  if new.status = 'driver_assigned' and new.driver_id is not null then
    -- We construct the webhook URL.
    -- In production, edge_function_base_url is set. Locally it defaults to the docker host.
    webhook_url := coalesce(
      current_setting('app.settings.edge_function_base_url', true),
      'http://host.docker.internal:54321/functions/v1'
    ) || '/dispatch_fcm';

    payload := jsonb_build_object(
      'type', tg_op,
      'table', tg_relname,
      'schema', tg_table_schema,
      'record', row_to_json(new),
      'old_record', case when tg_op = 'UPDATE' then row_to_json(old) else null end
    );

    -- Only call pg_net if it exists (avoids crashing local WSL tests which lack pg_net)
    if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net') then
      execute 'select net.http_post($1, body := $2)'
        using webhook_url, payload
        into request_id;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trips_fcm_webhook_trigger on public.trips;
create trigger trips_fcm_webhook_trigger
  after insert or update on public.trips
  for each row
  execute function public.trips_fcm_webhook();
