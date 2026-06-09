import { assertEquals } from "jsr:@std/assert";
import { buildAuthorizeUrl, buildRefreshTokenRequest, buildTokenRequest, needsTokenRefresh, parseTokenResponse } from "./exchange.ts";

Deno.test("buildAuthorizeUrl creates Supabase OAuth authorize URL", () => {
  const url = buildAuthorizeUrl({
    clientId: "client-1",
    redirectUri: "http://127.0.0.1:53682/callback",
    state: "state-1",
    scope: "projects:read database:read",
  });
  assertEquals(url.origin, "https://api.supabase.com");
  assertEquals(url.pathname, "/v1/oauth/authorize");
  assertEquals(url.searchParams.get("client_id"), "client-1");
  assertEquals(url.searchParams.get("redirect_uri"), "http://127.0.0.1:53682/callback");
  assertEquals(url.searchParams.get("response_type"), "code");
  assertEquals(url.searchParams.get("state"), "state-1");
  assertEquals(url.searchParams.get("scope"), "projects:read database:read");
});

Deno.test("buildTokenRequest encodes form body with auth code grant", () => {
  const req = buildTokenRequest({
    code: "abc",
    clientId: "cid",
    clientSecret: "csec",
    redirectUri: "connectum://oauth/callback",
  });
  assertEquals(req.url, "https://api.supabase.com/v1/oauth/token");
  assertEquals(req.headers["Content-Type"], "application/x-www-form-urlencoded");
  const params = new URLSearchParams(req.body);
  assertEquals(params.get("grant_type"), "authorization_code");
  assertEquals(params.get("code"), "abc");
  assertEquals(params.get("redirect_uri"), "connectum://oauth/callback");
});

Deno.test("parseTokenResponse extracts tokens + expiry", () => {
  const parsed = parseTokenResponse({
    access_token: "at", refresh_token: "rt", expires_in: 3600,
  });
  assertEquals(parsed.accessToken, "at");
  assertEquals(parsed.refreshToken, "rt");
  assertEquals(typeof parsed.expiresAt, "string");
});

Deno.test("buildRefreshTokenRequest encodes refresh grant", () => {
  const req = buildRefreshTokenRequest({
    refreshToken: "refresh-1",
    clientId: "cid",
    clientSecret: "csec",
  });
  assertEquals(req.url, "https://api.supabase.com/v1/oauth/token");
  const params = new URLSearchParams(req.body);
  assertEquals(params.get("grant_type"), "refresh_token");
  assertEquals(params.get("refresh_token"), "refresh-1");
});

Deno.test("needsTokenRefresh refreshes missing or near-expired values", () => {
  const now = new Date("2026-06-08T00:00:00Z");
  assertEquals(needsTokenRefresh(null, now), false);
  assertEquals(needsTokenRefresh("2026-06-08T00:02:00Z", now), true);
  assertEquals(needsTokenRefresh("2026-06-08T00:20:00Z", now), false);
});
