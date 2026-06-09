export interface AuthorizeUrlInput {
  clientId: string;
  redirectUri: string;
  state: string;
  scope?: string | null;
}

export function buildAuthorizeUrl(i: AuthorizeUrlInput): URL {
  const url = new URL("https://api.supabase.com/v1/oauth/authorize");
  url.searchParams.set("client_id", i.clientId);
  url.searchParams.set("redirect_uri", i.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("state", i.state);
  if (i.scope?.trim()) {
    url.searchParams.set("scope", i.scope.trim());
  }
  return url;
}

export interface TokenRequestInput {
  code: string; clientId: string; clientSecret: string; redirectUri: string;
}
export interface BuiltRequest { url: string; headers: Record<string, string>; body: string; }

export function buildTokenRequest(i: TokenRequestInput): BuiltRequest {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code: i.code,
    redirect_uri: i.redirectUri,
  }).toString();
  const basic = btoa(`${i.clientId}:${i.clientSecret}`);
  return {
    url: "https://api.supabase.com/v1/oauth/token",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basic}`,
    },
    body,
  };
}

export interface RefreshTokenRequestInput {
  refreshToken: string; clientId: string; clientSecret: string;
}

export function buildRefreshTokenRequest(i: RefreshTokenRequestInput): BuiltRequest {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: i.refreshToken,
  }).toString();
  const basic = btoa(`${i.clientId}:${i.clientSecret}`);
  return {
    url: "https://api.supabase.com/v1/oauth/token",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basic}`,
    },
    body,
  };
}

export function needsTokenRefresh(expiresAt: string | null | undefined, now = new Date()): boolean {
  if (!expiresAt) return false;
  const expires = new Date(expiresAt).getTime();
  if (Number.isNaN(expires)) return true;
  return expires - now.getTime() <= 5 * 60 * 1000;
}

export interface ParsedToken { accessToken: string; refreshToken: string | null; expiresAt: string; }
export function parseTokenResponse(raw: { access_token: string; refresh_token?: string; expires_in: number }): ParsedToken {
  return {
    accessToken: raw.access_token,
    refreshToken: raw.refresh_token ?? null,
    expiresAt: new Date(Date.now() + raw.expires_in * 1000).toISOString(),
  };
}
