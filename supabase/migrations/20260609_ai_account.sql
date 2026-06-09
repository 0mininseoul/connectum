-- Workspace-global Claude (AI) account. Tokens live in Vault; table holds refs only.
create table if not exists public.ai_account (
  id uuid primary key default gen_random_uuid(),
  label text not null default 'Claude',
  account_name text,
  access_token_ref text not null,
  refresh_token_ref text,
  expires_at timestamptz,
  scope text,
  created_at timestamptz not null default now()
);

alter table public.ai_account enable row level security;

-- Mirror existing *_account policy shape: authenticated users may read metadata;
-- inserts/updates happen via service_role inside Edge Functions only.
drop policy if exists ai_account_select on public.ai_account;
create policy ai_account_select on public.ai_account
  for select to authenticated using (true);

drop policy if exists ai_account_delete on public.ai_account;
create policy ai_account_delete on public.ai_account
  for delete to authenticated using (true);
