import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { requireInternalRequest, withInternalHeaders } from "./internal_auth.ts";

Deno.test("requireInternalRequest allows local calls when no secret is configured", () => {
  Deno.env.delete("CONNECTUM_INTERNAL_FUNCTION_SECRET");
  const req = new Request("https://example.test");
  assertEquals(requireInternalRequest(req), null);
});

Deno.test("requireInternalRequest rejects missing internal header when secret is configured", () => {
  Deno.env.set("CONNECTUM_INTERNAL_FUNCTION_SECRET", "test-secret");
  const req = new Request("https://example.test");
  assertEquals(requireInternalRequest(req)?.status, 401);
  Deno.env.delete("CONNECTUM_INTERNAL_FUNCTION_SECRET");
});

Deno.test("withInternalHeaders attaches configured internal secret", () => {
  Deno.env.set("CONNECTUM_INTERNAL_FUNCTION_SECRET", "test-secret");
  const headers = withInternalHeaders({ "Content-Type": "application/json" });
  assertEquals(headers.get("x-connectum-internal-secret"), "test-secret");
  assertEquals(headers.get("Content-Type"), "application/json");
  const req = new Request("https://example.test", { headers });
  assertEquals(requireInternalRequest(req), null);
  Deno.env.delete("CONNECTUM_INTERNAL_FUNCTION_SECRET");
});
