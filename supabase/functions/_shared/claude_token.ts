import { adminClient } from "./admin.ts";
import { getSecret, setSecret } from "./vault.ts";
import { claudeEnv } from "./claude_env.ts";
import { buildRefreshBody, needsRefresh, parseTokenResponse, TOKEN_CONTENT_TYPE } from "./claude_oauth.ts";

type Row = {
  id: string;
  access_token_ref: string;
  refresh_token_ref: string | null;
  expires_at: string | null;
};

// Returns a valid Claude OAuth access token for the single workspace account,
// refreshing via the refresh_token grant when within 5 minutes of expiry.
// Mirrors supabase_token.ts (no client secret — public PKCE client).
export async function tokenForClaudeAccount(): Promise<string> {
  const db = adminClient();
  const { data, error } = await db.from("ai_account")
    .select("id,access_token_ref,refresh_token_ref,expires_at")
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("ai_not_connected");
  const row = data as Row;
  const access = await getSecret(row.access_token_ref);
  if (!row.refresh_token_ref || !needsRefresh(row.expires_at)) return access;

  // Anthropic's subscription refresh tokens are single-use and rotate on every
  // refresh. Two concurrent refreshes reuse the same token, which Anthropic
  // treats as theft and revokes the whole family — bricking the connection until
  // a manual reconnect. Serialize: claim refresh_lock_at with an atomic
  // conditional UPDATE (Postgres row-locks it, so exactly one caller wins).
  const staleIso = new Date(Date.now() - 30_000).toISOString();
  const { data: claimed, error: claimErr } = await db.from("ai_account")
    .update({ refresh_lock_at: new Date().toISOString() })
    .eq("id", row.id)
    .or(`refresh_lock_at.is.null,refresh_lock_at.lt.${staleIso}`)
    .select("id");

  // Only wait if we definitively LOST the claim. A transient error on the claim
  // statement means we can't coordinate — fall through and refresh ourselves
  // rather than poll and return a stale/expired token.
  if (!claimErr && !claimed?.length) {
    // Another request holds the lock and is refreshing. Wait for it to store the
    // rotated token, then use that — never send the old refresh token ourselves.
    for (let i = 0; i < 12; i++) {
      await new Promise((r) => setTimeout(r, 600));
      const { data: fresh } = await db.from("ai_account")
        .select("access_token_ref,expires_at").eq("id", row.id).maybeSingle();
      if (fresh && !needsRefresh(fresh.expires_at)) return await getSecret(fresh.access_token_ref);
    }
    // Holder never finished (crashed mid-refresh). Return the current token; the
    // upstream call may 401 → reauth prompt, which is safe vs. reusing the token.
    return access;
  }

  try {
    const refresh = await getSecret(row.refresh_token_ref);
    const res = await fetch(claudeEnv.tokenUrl(), {
      method: "POST",
      headers: { "Content-Type": TOKEN_CONTENT_TYPE },
      body: buildRefreshBody({ refreshToken: refresh, clientId: claudeEnv.clientId() }),
    });
    if (!res.ok) throw new Error(`claude_refresh_failed:${res.status}:${await res.text()}`);
    const tokens = parseTokenResponse(await res.json());
    await setSecret(row.access_token_ref, tokens.accessToken);
    if (tokens.refreshToken) await setSecret(row.refresh_token_ref, tokens.refreshToken);
    await db.from("ai_account")
      .update({ expires_at: tokens.expiresAt, refresh_lock_at: null }).eq("id", row.id);
    return tokens.accessToken;
  } catch (e) {
    // Release the claim so the next request can retry instead of waiting 30s.
    await db.from("ai_account").update({ refresh_lock_at: null }).eq("id", row.id);
    throw e;
  }
}
