import { corsHeaders } from "../_shared/cors.ts";
import { supabaseOAuthCallbackUri, supabaseOAuthClientId, supabaseOAuthScopes } from "../_shared/oauth_env.ts";
import { buildAuthorizeUrl } from "../oauth-supabase/exchange.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { state } = await req.json();
    if (!state || typeof state !== "string") throw new Error("state is required");
    const clientId = supabaseOAuthClientId();
    if (!clientId) throw new Error("CONNECTUM_SUPABASE_OAUTH_CLIENT_ID is not configured");
    const authorizeUrl = buildAuthorizeUrl({
      clientId,
      redirectUri: supabaseOAuthCallbackUri(),
      state,
      scope: supabaseOAuthScopes(),
    });
    return new Response(JSON.stringify({ authorize_url: authorizeUrl.toString() }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) {
  Deno.serve(handle);
}
