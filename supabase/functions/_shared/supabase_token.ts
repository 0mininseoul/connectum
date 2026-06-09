import { adminClient } from "./admin.ts";
import { supabaseOAuthClientId, supabaseOAuthClientSecret } from "./oauth_env.ts";
import { getSecret, setSecret } from "./vault.ts";
import { buildRefreshTokenRequest, needsTokenRefresh, parseTokenResponse } from "../oauth-supabase/exchange.ts";

type SupabaseAccountTokenRow = {
  access_token_ref: string;
  refresh_token_ref?: string | null;
  expires_at?: string | null;
};

export async function tokenForSupabaseAccount(accountId: string): Promise<string> {
  const db = adminClient();
  const { data: account, error } = await db.from("supabase_account")
    .select("access_token_ref,refresh_token_ref,expires_at")
    .eq("id", accountId)
    .single();
  if (error) throw error;
  const row = account as SupabaseAccountTokenRow;
  const currentAccessToken = await getSecret(row.access_token_ref);

  if (!row.refresh_token_ref || !needsTokenRefresh(row.expires_at)) {
    return currentAccessToken;
  }

  const refreshToken = await getSecret(row.refresh_token_ref);
  const clientId = supabaseOAuthClientId();
  const clientSecret = supabaseOAuthClientSecret();
  if (!clientId || !clientSecret) throw new Error("Connectum Supabase OAuth client is not configured");
  const built = buildRefreshTokenRequest({
    refreshToken,
    clientId,
    clientSecret,
  });
  const tokenRes = await fetch(built.url, { method: "POST", headers: built.headers, body: built.body });
  if (!tokenRes.ok) throw new Error(`Supabase OAuth refresh failed: ${tokenRes.status}: ${await tokenRes.text()}`);

  const tokens = parseTokenResponse(await tokenRes.json());
  await setSecret(row.access_token_ref, tokens.accessToken);
  if (tokens.refreshToken) {
    await setSecret(row.refresh_token_ref, tokens.refreshToken);
  }
  const { error: updateError } = await db.from("supabase_account")
    .update({ expires_at: tokens.expiresAt })
    .eq("id", accountId);
  if (updateError) throw updateError;
  return tokens.accessToken;
}
