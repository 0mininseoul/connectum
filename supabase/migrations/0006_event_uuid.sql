-- Dedup key for Amplitude events (the export's per-event `uuid`).
alter table public.crm_user_event add column if not exists event_uuid text;
create unique index if not exists crm_user_event_uuid_key on public.crm_user_event (event_uuid);
