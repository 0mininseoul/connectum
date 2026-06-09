-- Latest distributable build advertised to the app's "check for update" button.
create table if not exists public.app_release (
  id uuid primary key default gen_random_uuid(),
  version text not null,
  dmg_url text not null,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.app_release enable row level security;

-- Read-only to signed-in users; rows are inserted out-of-band on release.
drop policy if exists app_release_select on public.app_release;
create policy app_release_select on public.app_release
  for select to authenticated using (true);
