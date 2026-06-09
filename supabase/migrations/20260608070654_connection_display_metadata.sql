alter table public.supabase_account
  add column if not exists account_name text;

alter table public.amplitude_account
  add column if not exists account_name text,
  add column if not exists project_name text;

alter table public.axiom_account
  add column if not exists account_name text,
  add column if not exists datasets text[] not null default '{}';

alter table public.service
  add column if not exists supabase_project_name text,
  add column if not exists amplitude_project_name text;

update public.supabase_account
set account_name = label
where account_name is null
  and label like '%@%';

update public.amplitude_account
set account_name = label
where account_name is null
  and label like '%@%';

update public.axiom_account
set account_name = label
where account_name is null
  and label like '%@%';
