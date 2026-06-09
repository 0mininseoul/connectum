const DEFAULT_LOOPBACK_URI = "http://127.0.0.1:53682/callback";
const DEFAULT_SUPABASE_OAUTH_SCOPES = "projects:read database:read";

function env(name: string): string | null {
  const value = Deno.env.get(name);
  return value && value.trim().length > 0 ? value : null;
}

export function supabaseOAuthClientId(): string | null {
  return env("CONNECTUM_SUPABASE_OAUTH_CLIENT_ID") ?? env("SUPABASE_OAUTH_CLIENT_ID");
}

export function supabaseOAuthClientSecret(): string | null {
  return env("CONNECTUM_SUPABASE_OAUTH_CLIENT_SECRET") ?? env("SUPABASE_OAUTH_CLIENT_SECRET");
}

export function supabaseOAuthScopes(): string {
  return env("CONNECTUM_SUPABASE_OAUTH_SCOPES")
    ?? env("SUPABASE_OAUTH_SCOPES")
    ?? DEFAULT_SUPABASE_OAUTH_SCOPES;
}

export function supabaseOAuthCallbackUri(): string {
  return env("CONNECTUM_SUPABASE_OAUTH_CALLBACK_URI")
    ?? env("CONNECTUM_SUPABASE_OAUTH_REDIRECT_URI")
    ?? env("CONNECTUM_OAUTH_REDIRECT_URI")
    ?? `${Deno.env.get("SUPABASE_URL")}/functions/v1/oauth-supabase-callback`;
}

export function connectumAppLoopbackUri(): string {
  return env("CONNECTUM_APP_OAUTH_LOOPBACK_URI") ?? DEFAULT_LOOPBACK_URI;
}
