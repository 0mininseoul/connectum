-- Serialize Supabase OAuth token refreshes (same hazard as the Claude one in
-- 20260610110000): Supabase rotates the refresh token on every use, so two
-- concurrent refreshes reuse a consumed token and Supabase revokes the whole
-- family ("No such refresh token found"), bricking every Management-API call
-- until the account is re-authorized. tokenForSupabaseAccount() claims this
-- timestamp with an atomic conditional update so exactly one caller refreshes.
alter table public.supabase_account
  add column if not exists refresh_lock_at timestamptz;
