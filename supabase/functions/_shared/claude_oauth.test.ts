import { assert, assertEquals } from "jsr:@std/assert";
import {
  buildAuthorizeUrl,
  buildCodeExchangeBody,
  buildRefreshBody,
  needsRefresh,
  parseTokenResponse,
} from "./claude_oauth.ts";

Deno.test("authorize url has pkce + scope + redirect", () => {
  const u = buildAuthorizeUrl({
    authorizeUrl: "https://claude.ai/oauth/authorize",
    clientId: "cid",
    redirectUri: "http://127.0.0.1:53682/callback",
    state: "st",
    scope: "user:inference",
    codeChallenge: "chal",
  });
  assertEquals(u.searchParams.get("response_type"), "code");
  assertEquals(u.searchParams.get("client_id"), "cid");
  assertEquals(u.searchParams.get("code_challenge"), "chal");
  assertEquals(u.searchParams.get("code_challenge_method"), "S256");
  assertEquals(u.searchParams.get("state"), "st");
  assertEquals(u.searchParams.get("redirect_uri"), "http://127.0.0.1:53682/callback");
});

Deno.test("code exchange body carries verifier, no secret", () => {
  const b = buildCodeExchangeBody({
    code: "c",
    codeVerifier: "v",
    clientId: "cid",
    redirectUri: "http://127.0.0.1:53682/callback",
  });
  const p = new URLSearchParams(b);
  assertEquals(p.get("grant_type"), "authorization_code");
  assertEquals(p.get("code"), "c");
  assertEquals(p.get("code_verifier"), "v");
  assertEquals(p.get("client_id"), "cid");
  assert(!b.includes("client_secret"));
});

Deno.test("refresh body uses refresh grant", () => {
  const p = new URLSearchParams(buildRefreshBody({ refreshToken: "r", clientId: "cid" }));
  assertEquals(p.get("grant_type"), "refresh_token");
  assertEquals(p.get("refresh_token"), "r");
  assertEquals(p.get("client_id"), "cid");
});

Deno.test("parse token response computes expiry", () => {
  const t = parseTokenResponse({ access_token: "a", refresh_token: "r", expires_in: 3600 });
  assertEquals(t.accessToken, "a");
  assertEquals(t.refreshToken, "r");
  assert(new Date(t.expiresAt).getTime() > Date.now());
});

Deno.test("needsRefresh true within 5 min window", () => {
  assertEquals(needsRefresh(new Date(Date.now() + 60_000).toISOString()), true);
  assertEquals(needsRefresh(new Date(Date.now() + 3600_000).toISOString()), false);
  assertEquals(needsRefresh(null), true);
});
