-- Read a Vault secret by name (server-side use only).
create or replace function public.vault_get(secret_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  select decrypted_secret into v from vault.decrypted_secrets where name = secret_name;
  return v;
end $$;
revoke all on function public.vault_get(text) from public, anon, authenticated;
