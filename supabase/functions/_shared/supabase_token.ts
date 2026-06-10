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

  // Serialize refreshes. Supabase rotates the refresh token on every use, so two
  // concurrent refreshes reuse one (consumed) token and Supabase revokes the
  // whole family ("No such refresh token found"). Claim refresh_lock_at with an
  // atomic conditional UPDATE — exactly one caller refreshes; the rest wait for
  // the rotated token and reuse it instead of sending the consumed one.
  const staleIso = new Date(Date.now() - 30_000).toISOString();
  const { data: claimed, error: claimErr } = await db.from("supabase_account")
    .update({ refresh_lock_at: new Date().toISOString() })
    .eq("id", accountId)
    .or(`refresh_lock_at.is.null,refresh_lock_at.lt.${staleIso}`)
    .select("id");

  // Only wait if we definitively LOST the claim. A transient error on the claim
  // statement means we can't coordinate — fall through and refresh ourselves
  // rather than poll and return a stale/expired token (a lone caller has no
  // contender to double-refresh against).
  if (!claimErr && !claimed?.length) {
    for (let i = 0; i < 12; i++) {
      await new Promise((r) => setTimeout(r, 600));
      const { data: fresh } = await db.from("supabase_account")
        .select("access_token_ref,expires_at").eq("id", accountId).maybeSingle();
      if (fresh && !needsTokenRefresh(fresh.expires_at)) return await getSecret(fresh.access_token_ref);
    }
    return currentAccessToken;
  }

  try {
    const refreshToken = await getSecret(row.refresh_token_ref);
    const clientId = supabaseOAuthClientId();
    const clientSecret = supabaseOAuthClientSecret();
    if (!clientId || !clientSecret) throw new Error("Connectum Supabase OAuth client is not configured");
    const built = buildRefreshTokenRequest({ refreshToken, clientId, clientSecret });
    const tokenRes = await fetch(built.url, { method: "POST", headers: built.headers, body: built.body });
    if (!tokenRes.ok) throw new Error(`Supabase OAuth refresh failed: ${tokenRes.status}: ${await tokenRes.text()}`);

    const tokens = parseTokenResponse(await tokenRes.json());
    await setSecret(row.access_token_ref, tokens.accessToken);
    if (tokens.refreshToken) await setSecret(row.refresh_token_ref, tokens.refreshToken);
    const { error: updateError } = await db.from("supabase_account")
      .update({ expires_at: tokens.expiresAt, refresh_lock_at: null })
      .eq("id", accountId);
    if (updateError) throw updateError;
    return tokens.accessToken;
  } catch (e) {
    await db.from("supabase_account").update({ refresh_lock_at: null }).eq("id", accountId);
    throw e;
  }
}
