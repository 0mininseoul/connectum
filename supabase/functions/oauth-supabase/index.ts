import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import { supabaseOAuthCallbackUri, supabaseOAuthClientId, supabaseOAuthClientSecret } from "../_shared/oauth_env.ts";
import { buildTokenRequest, parseTokenResponse } from "./exchange.ts";

// App sends { code, label } after the OAuth redirect lands on the app's loopback
// listener. Supabase OAuth requires https or localhost callbacks (custom schemes
// are rejected), so we use an RFC 8252 loopback redirect. The redirect_uri here
// MUST match the one registered on the OAuth app and used in the authorize step.
// Client secret stays here (server). Tokens are written to Vault; only refs land in the table.
type SupabaseProfile = {
  primary_email?: string | null;
  email?: string | null;
  username?: string | null;
  name?: string | null;
};

function displayNameFromProfile(profile: SupabaseProfile): string | null {
  return profile.primary_email ?? profile.email ?? profile.username ?? profile.name ?? null;
}

async function handleOauthSupabase(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { code, label } = await req.json();
    const clientId = supabaseOAuthClientId();
    const clientSecret = supabaseOAuthClientSecret();
    if (!clientId || !clientSecret) throw new Error("Connectum Supabase OAuth client is not configured");
    const built = buildTokenRequest({
      code,
      clientId,
      clientSecret,
      redirectUri: supabaseOAuthCallbackUri(),
    });
    const tokenRes = await fetch(built.url, { method: "POST", headers: built.headers, body: built.body });
    if (!tokenRes.ok) {
      return new Response(JSON.stringify({ error: await tokenRes.text() }), { status: 502, headers: corsHeaders });
    }
    const tokens = parseTokenResponse(await tokenRes.json());
    if (!tokens.refreshToken) throw new Error("Supabase OAuth response did not include refresh_token");
    const profile = await mgmtGet<SupabaseProfile>("/v1/profile", tokens.accessToken).catch(() => null);
    const accountName = profile ? displayNameFromProfile(profile) : null;

    const db = adminClient();
    const accessRef = `supabase_oauth_access_${crypto.randomUUID()}`;
    const refreshRef = `supabase_oauth_refresh_${crypto.randomUUID()}`;
    await db.rpc("vault_set", { secret_name: accessRef, secret_value: tokens.accessToken });
    await db.rpc("vault_set", { secret_name: refreshRef, secret_value: tokens.refreshToken });
    const { data, error } = await db.from("supabase_account").insert({
      label: label ?? accountName ?? "Supabase",
      account_name: accountName,
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
