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
  await db.from("ai_account").update({ expires_at: tokens.expiresAt }).eq("id", row.id);
  return tokens.accessToken;
}
