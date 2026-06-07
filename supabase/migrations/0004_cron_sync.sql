-- 0004_cron_sync.sql — run the sync Edge Function every 30 minutes.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Store the function URL + service key for pg_net to call. In hosted Supabase
-- these come from project settings; locally they target the local gateway.
-- Replace the placeholders at deploy time (documented in README deploy section).
do $$
begin
  perform cron.schedule(
    'connectum-sync',
    '*/30 * * * *',
    $cron$
      select net.http_post(
        url := current_setting('app.sync_function_url', true),
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
        ),
        body := '{}'::jsonb
      );
    $cron$
  );
end $$;
