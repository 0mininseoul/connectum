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

export interface ParsedToken { accessToken: string; refreshToken: string; expiresAt: string; }
export function parseTokenResponse(raw: { access_token: string; refresh_token: string; expires_in: number }): ParsedToken {
  return {
    accessToken: raw.access_token,
    refreshToken: raw.refresh_token,
    expiresAt: new Date(Date.now() + raw.expires_in * 1000).toISOString(),
  };
}
