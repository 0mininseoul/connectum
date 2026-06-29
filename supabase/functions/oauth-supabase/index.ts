import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import {
  supabaseOAuthCallbackUri,
  supabaseOAuthClientId,
  supabaseOAuthClientSecret,
} from "../_shared/oauth_env.ts";
import {
  displayNameFromSupabaseProfile,
  type SupabaseProfile,
} from "../_shared/supabase_profile.ts";
import { buildRefreshTokenRequest, buildTokenRequest, parseTokenResponse } from "./exchange.ts";

type OAuthRequest = {
  code?: string;
  label?: string;
  storage?: string;
  refresh_token?: string;
};

function localTokenResponse(tokens: ReturnType<typeof parseTokenResponse>, accountName: string | null): Response {
  return new Response(JSON.stringify({
    access_token: tokens.accessToken,
    refresh_token: tokens.refreshToken,
    expires_at: tokens.expiresAt,
    account_name: accountName,
  }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// App sends { code, label } after the OAuth redirect lands on the app's loopback
// listener. Supabase OAuth requires https or localhost callbacks (custom schemes
// are rejected), so we use an RFC 8252 loopback redirect. The redirect_uri here
// MUST match the one registered on the OAuth app and used in the authorize step.
// Client secret stays here (server). Tokens are written to Vault; only refs land in the table.
async function handleOauthSupabase(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { code, label, storage, refresh_token } = await req.json() as OAuthRequest;
    const clientId = supabaseOAuthClientId();
    const clientSecret = supabaseOAuthClientSecret();
    if (!clientId || !clientSecret) {
      throw new Error("Connectum Supabase OAuth client is not configured");
    }
    if (!refresh_token && !code) {
      throw new Error("code is required");
    }
    const built = refresh_token
      ? buildRefreshTokenRequest({ refreshToken: refresh_token, clientId, clientSecret })
      : buildTokenRequest({
        code: code!,
        clientId,
        clientSecret,
        redirectUri: supabaseOAuthCallbackUri(),
      });
    const tokenRes = await fetch(built.url, {
      method: "POST",
      headers: built.headers,
      body: built.body,
    });
    if (!tokenRes.ok) {
      return new Response(JSON.stringify({ error: await tokenRes.text() }), {
        status: 502,
        headers: corsHeaders,
      });
    }
    const tokens = parseTokenResponse(await tokenRes.json());
    if (!refresh_token && !tokens.refreshToken) {
      throw new Error("Supabase OAuth response did not include refresh_token");
    }
    const profile = await mgmtGet<SupabaseProfile>(
      "/v1/profile",
      tokens.accessToken,
    ).catch(() => null);
    const accountName = displayNameFromSupabaseProfile(profile);

    if (storage === "local_keychain") {
      return localTokenResponse(tokens, accountName);
    }

    const db = adminClient();
    const accessRef = `supabase_oauth_access_${crypto.randomUUID()}`;
    const refreshRef = `supabase_oauth_refresh_${crypto.randomUUID()}`;
    await db.rpc("vault_set", {
      secret_name: accessRef,
      secret_value: tokens.accessToken,
    });
    await db.rpc("vault_set", {
      secret_name: refreshRef,
      secret_value: tokens.refreshToken,
    });
    const { data, error } = await db.from("supabase_account").insert({
      label: label ?? accountName ?? "Supabase",
      account_name: accountName,
      access_token_ref: accessRef,
      refresh_token_ref: refreshRef,
      expires_at: tokens.expiresAt,
    }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
}

if (import.meta.main) {
  Deno.serve(handleOauthSupabase);
}
