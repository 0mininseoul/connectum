import { assertEquals } from "jsr:@std/assert";
import { buildTokenRequest, parseTokenResponse } from "./exchange.ts";

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
