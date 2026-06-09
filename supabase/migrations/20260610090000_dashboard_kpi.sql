-- Per-service dashboard KPIs (source of truth in Supabase; replaces device-local
-- storage). System KPIs are seeded per service; custom KPIs carry a computation spec.
create table if not exists public.dashboard_kpi (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.service(id) on delete cascade,
  kind text not null,                 -- total_users | contact_rate | contacted | custom
  title text not null,
  prompt text,                        -- the user's description (custom)
  spec jsonb,                         -- structured computation spec (custom)
  unit text,                          -- count | percent (custom)
  value double precision,             -- last computed value (custom)
  position double precision not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists dashboard_kpi_service_idx on public.dashboard_kpi (service_id, position);

alter table public.dashboard_kpi enable row level security;

drop policy if exists dashboard_kpi_select on public.dashboard_kpi;
create policy dashboard_kpi_select on public.dashboard_kpi for select to authenticated using (true);
drop policy if exists dashboard_kpi_insert on public.dashboard_kpi;
create policy dashboard_kpi_insert on public.dashboard_kpi for insert to authenticated with check (true);
drop policy if exists dashboard_kpi_update on public.dashboard_kpi;
create policy dashboard_kpi_update on public.dashboard_kpi for update to authenticated using (true);
drop policy if exists dashboard_kpi_delete on public.dashboard_kpi;
create policy dashboard_kpi_delete on public.dashboard_kpi for delete to authenticated using (true);
