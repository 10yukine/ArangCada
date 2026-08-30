-- dispatch_fcm is deployed with --no-verify-jwt (a DB trigger via pg_net
-- cannot attach a user JWT), which makes it a publicly reachable URL. This
-- migration makes the trigger send a shared secret header so the function
-- can reject any call that did not come from this trigger.
--
-- The secret itself lives in Supabase Vault (`vault.secrets`, name
-- 'fcm_webhook_secret'), created out-of-band by `supabase db query` -- never
-- in a migration file, so it is never committed to Git. `ALTER DATABASE ...
-- SET app.settings.*` was tried first and rejected with a permission error
-- on this project (`42501: permission denied to set parameter`), so Vault is
-- the mechanism here rather than a custom GUC.
--
-- The Edge Function base URL is NOT a secret (it is this project's public
-- functions host) and is hardcoded directly below rather than read from a
-- setting, since the earlier `current_setting('app.settings.edge_function_
-- base_url', ...)` approach hit the same permission wall.
create or replace function public.trips_fcm_webhook()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_id bigint;
  webhook_url text := 'https://zzcqyhtizvkuhrpfneth.supabase.co/functions/v1/dispatch_fcm';
  payload jsonb;
  webhook_secret text;
begin
  -- Skip if status hasn't changed to driver_assigned
  if tg_op = 'UPDATE' and old.status = new.status then
    return new;
  end if;

  if new.status = 'driver_assigned' and new.driver_id is not null then
    select decrypted_secret into webhook_secret
      from vault.decrypted_secrets
     where name = 'fcm_webhook_secret'
     limit 1;

    payload := jsonb_build_object(
      'type', tg_op,
      'table', tg_relname,
      'schema', tg_table_schema,
      'record', row_to_json(new),
      'old_record', case when tg_op = 'UPDATE' then row_to_json(old) else null end
    );

    -- Only call pg_net if it exists (avoids crashing local WSL tests which lack pg_net)
    if exists (select 1 from pg_catalog.pg_extension where extname = 'pg_net') then
      execute 'select net.http_post($1, body := $2, headers := $3)'
        using
          webhook_url,
          payload,
          jsonb_build_object(
            'Content-Type', 'application/json',
            'x-webhook-secret', coalesce(webhook_secret, '')
          )
        into request_id;
    end if;
  end if;

  return new;
end;
$$;
