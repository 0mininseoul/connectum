-- Wrapper so Edge Functions can store secrets in Vault by name.
create or replace function public.vault_set(secret_name text, secret_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform vault.create_secret(secret_value, secret_name);
end $$;
revoke all on function public.vault_set(text, text) from public, anon, authenticated;
