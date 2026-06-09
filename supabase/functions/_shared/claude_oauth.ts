// Claude (Anthropic) subscription OAuth — public client + PKCE (no client secret).
// Mirrors the Supabase OAuth exchange shape, but uses code_verifier instead of a secret.

export interface AuthorizeInput {
  authorizeUrl: string;
  clientId: string;
  redirectUri: string;
  state: string;
  scope: string;
  codeChallenge: string;
}

export function buildAuthorizeUrl(i: AuthorizeInput): URL {
  const u = new URL(i.authorizeUrl);
  u.searchParams.set("code", "true");
  u.searchParams.set("response_type", "code");
  u.searchParams.set("client_id", i.clientId);
  u.searchParams.set("redirect_uri", i.redirectUri);
  u.searchParams.set("scope", i.scope);
  u.searchParams.set("state", i.state);
  u.searchParams.set("code_challenge", i.codeChallenge);
  u.searchParams.set("code_challenge_method", "S256");
  return u;
}

export interface CodeExchangeInput {
  code: string;
  state?: string;
  codeVerifier: string;
  clientId: string;
  redirectUri: string;
}

// Claude's token endpoint expects a JSON body (not form-urlencoded) and the state.
export function buildCodeExchangeBody(i: CodeExchangeInput): string {
  const body: Record<string, string> = {
    grant_type: "authorization_code",
    code: i.code,
    redirect_uri: i.redirectUri,
    client_id: i.clientId,
    code_verifier: i.codeVerifier,
  };
  if (i.state) body.state = i.state;
  return JSON.stringify(body);
}

export interface RefreshInput {
  refreshToken: string;
  clientId: string;
}

export function buildRefreshBody(i: RefreshInput): string {
  return JSON.stringify({
    grant_type: "refresh_token",
    refresh_token: i.refreshToken,
    client_id: i.clientId,
  });
}

export const TOKEN_CONTENT_TYPE = "application/json";

export interface ParsedToken {
  accessToken: string;
  refreshToken: string | null;
  expiresAt: string;
}

export function parseTokenResponse(
  raw: { access_token: string; refresh_token?: string; expires_in?: number },
): ParsedToken {
  return {
    accessToken: raw.access_token,
    refreshToken: raw.refresh_token ?? null,
    expiresAt: new Date(Date.now() + (raw.expires_in ?? 0) * 1000).toISOString(),
  };
}

export function needsRefresh(expiresAt: string | null | undefined, now = new Date()): boolean {
  if (!expiresAt) return true;
  const e = new Date(expiresAt).getTime();
  if (Number.isNaN(e)) return true;
  return e - now.getTime() <= 5 * 60 * 1000;
}
