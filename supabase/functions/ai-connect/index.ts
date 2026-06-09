import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { claudeEnv } from "../_shared/claude_env.ts";
import { buildCodeExchangeBody, parseTokenResponse } from "../_shared/claude_oauth.ts";

// Body: { code, code_verifier, redirect_uri }. Exchanges the PKCE auth code for
// Claude subscription tokens and stores them in Vault; ai_account holds refs only.
// Single workspace account: a new connect replaces any previous one.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { code, code_verifier, redirect_uri } = await req.json();
    if (!code || !code_verifier) throw new Error("missing code/code_verifier");

    const res = await fetch(claudeEnv.tokenUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: buildCodeExchangeBody({
        code,
        codeVerifier: code_verifier,
        clientId: claudeEnv.clientId(),
        redirectUri: redirect_uri ?? "http://127.0.0.1:53682/callback",
      }),
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ error: await res.text() }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const tokens = parseTokenResponse(await res.json());

    const db = adminClient();
    // Clear any existing account (single workspace-global Claude connection).
    await db.from("ai_account").delete().not("id", "is", null);

    const accessRef = `claude_oauth_access_${crypto.randomUUID()}`;
    const refreshRef = `claude_oauth_refresh_${crypto.randomUUID()}`;
    await setSecret(accessRef, tokens.accessToken);
    if (tokens.refreshToken) await setSecret(refreshRef, tokens.refreshToken);

    const { data, error } = await db.from("ai_account").insert({
      label: "Claude",
      access_token_ref: accessRef,
      refresh_token_ref: tokens.refreshToken ? refreshRef : null,
      expires_at: tokens.expiresAt,
      scope: claudeEnv.scope(),
    }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) Deno.serve(handle);
