-- Columns the operational-DB table should show for a service's user table
-- (chosen in the service-creation wizard). Names index into crm_user.supabase_profile.
alter table public.service_table
  add column if not exists display_columns jsonb not null default '[]'::jsonb;
