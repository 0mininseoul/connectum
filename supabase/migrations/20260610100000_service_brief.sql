-- Per-service qualitative context brief, authored/maintained by Claude.
-- Injected into ai-chat's system prompt so the assistant understands the service.
create table if not exists public.service_brief (
  service_id uuid primary key references public.service(id) on delete cascade,
  sections jsonb not null default '{}'::jsonb,  -- {one_liner, icp, activation, signal_glossary, business_model, current_focus}
  status text not null default 'empty',          -- 'empty' | 'ready'
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.service_brief enable row level security;

drop policy if exists service_brief_select on public.service_brief;
create policy service_brief_select on public.service_brief for select to authenticated using (true);
drop policy if exists service_brief_insert on public.service_brief;
create policy service_brief_insert on public.service_brief for insert to authenticated with check (true);
drop policy if exists service_brief_update on public.service_brief;
create policy service_brief_update on public.service_brief for update to authenticated using (true);
drop policy if exists service_brief_delete on public.service_brief;
create policy service_brief_delete on public.service_brief for delete to authenticated using (true);
