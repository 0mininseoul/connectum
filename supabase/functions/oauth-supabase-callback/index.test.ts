import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loopbackRedirect, loopbackUriFromState } from "./index.ts";

function stateFor(loopback: string): string {
  const raw = JSON.stringify({ v: 1, nonce: "nonce-1", loopback });
  return `connectum.${btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")}`;
}

Deno.test("loopbackUriFromState accepts localhost callback ports", () => {
  const state = stateFor("http://127.0.0.1:54321/callback");

  assertEquals(loopbackUriFromState(state), "http://127.0.0.1:54321/callback");
});

Deno.test("loopbackUriFromState rejects external redirects", () => {
  const state = stateFor("https://example.com/callback");

  assertEquals(loopbackUriFromState(state), null);
});

Deno.test("loopbackRedirect keeps OAuth params on dynamic localhost target", () => {
  const state = stateFor("http://127.0.0.1:54322/callback");
  const target = loopbackRedirect(
    new Request(`https://connectum.test/callback?code=abc&state=${encodeURIComponent(state)}`),
  );

  assertEquals(target.origin, "http://127.0.0.1:54322");
  assertEquals(target.pathname, "/callback");
  assertEquals(target.searchParams.get("code"), "abc");
  assertEquals(target.searchParams.get("state"), state);
});
