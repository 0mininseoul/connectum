import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { buildTokenRequest, parseTokenResponse } from "./exchange.ts";

// App sends { code, label } after ASWebAuthenticationSession returns the OAuth code.
// Client secret stays here (server). Tokens are written to Vault; only refs land in the table.
async function handleOauthSupabase(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { code, label } = await req.json();
    const built = buildTokenRequest({
      code,
      clientId: Deno.env.get("SUPABASE_OAUTH_CLIENT_ID")!,
      clientSecret: Deno.env.get("SUPABASE_OAUTH_CLIENT_SECRET")!,
      redirectUri: "connectum://oauth/callback",
    });
    const tokenRes = await fetch(built.url, { method: "POST", headers: built.headers, body: built.body });
    if (!tokenRes.ok) {
      return new Response(JSON.stringify({ error: await tokenRes.text() }), { status: 502, headers: corsHeaders });
    }
    const tokens = parseTokenResponse(await tokenRes.json());

    const db = adminClient();
    const accessRef = `supabase_oauth_access_${crypto.randomUUID()}`;
    const refreshRef = `supabase_oauth_refresh_${crypto.randomUUID()}`;
    await db.rpc("vault_set", { secret_name: accessRef, secret_value: tokens.accessToken });
    await db.rpc("vault_set", { secret_name: refreshRef, secret_value: tokens.refreshToken });
    const { data, error } = await db.from("supabase_account").insert({
      label: label ?? "Supabase",
      access_token_ref: accessRef,
      refresh_token_ref: refreshRef,
      expires_at: tokens.expiresAt,
    }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) {
  Deno.serve(handleOauthSupabase);
}
