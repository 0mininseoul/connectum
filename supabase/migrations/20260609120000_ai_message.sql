-- Persistent per-service AI chat history (one thread per service).
create table if not exists public.ai_message (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.service(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists ai_message_service_idx on public.ai_message (service_id, created_at);

alter table public.ai_message enable row level security;

drop policy if exists ai_message_select on public.ai_message;
create policy ai_message_select on public.ai_message
  for select to authenticated using (true);

drop policy if exists ai_message_insert on public.ai_message;
create policy ai_message_insert on public.ai_message
  for insert to authenticated with check (true);

drop policy if exists ai_message_delete on public.ai_message;
create policy ai_message_delete on public.ai_message
  for delete to authenticated using (true);
