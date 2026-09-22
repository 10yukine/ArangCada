-- Expands public.trips_fcm_webhook() to dispatch push notifications for all
-- major commuter and driver trip lifecycle events, rather than driver_assigned only.
--
-- Transitions covered:
--   driver_assigned       -> Push to driver ("New Ride Offer")
--   accepted              -> Push to commuter ("Driver On The Way")
--   driver_en_route       -> Push to commuter ("Driver En Route")
--   arrived               -> Push to commuter ("Driver Arrived")
--   completed             -> Push to commuter ("Trip Completed")
--   cancelled_by_rider    -> Push to driver ("Ride Cancelled", if driver was assigned)
--   cancelled_by_driver   -> Push to commuter ("Ride Cancelled")
--   no_driver_available   -> Push to commuter ("No Driver Available")

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
  -- Skip if status hasn't changed
  if tg_op = 'UPDATE' and old.status = new.status then
    return new;
  end if;

  if new.status in (
    'driver_assigned',
    'accepted',
    'driver_en_route',
    'arrived',
    'completed',
    'cancelled_by_rider',
    'cancelled_by_driver',
    'no_driver_available'
  ) then
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
