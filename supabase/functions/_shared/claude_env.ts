// Claude OAuth + API constants. All overridable via Edge secrets so the
// (potentially fragile) endpoints/identifiers can be swapped without redeploy.

function env(name: string, fallback: string): string {
  const v = Deno.env.get(name);
  return v && v.trim().length > 0 ? v : fallback;
}
function envOpt(name: string): string | null {
  const v = Deno.env.get(name);
  return v && v.trim().length > 0 ? v : null;
}

export const claudeEnv = {
  clientId: () => env("CLAUDE_OAUTH_CLIENT_ID", ""),
  authorizeUrl: () => env("CLAUDE_OAUTH_AUTHORIZE_URL", "https://platform.claude.com/oauth/authorize"),
  tokenUrl: () => env("CLAUDE_OAUTH_TOKEN_URL", "https://platform.claude.com/v1/oauth/token"),
  scope: () => env("CLAUDE_OAUTH_SCOPE", "org:create_api_key user:profile user:inference"),
  apiUrl: () => env("CLAUDE_API_URL", "https://api.anthropic.com/v1/messages"),
  oauthBeta: () => env("CLAUDE_OAUTH_BETA", "oauth-2025-04-20"),
  model: () => env("CLAUDE_MODEL", "claude-sonnet-4-6"),
  apiKey: () => envOpt("CLAUDE_API_KEY"),
};
