import { assertEquals } from "jsr:@std/assert";
import { parseCurrentUser, parsePrimaryOrg } from "./metadata.ts";

Deno.test("parseCurrentUser prefers provider email", () => {
  assertEquals(
    parseCurrentUser({ email: "user@example.com", name: "User Name" }),
    "user@example.com",
  );
});

Deno.test("parseCurrentUser falls back to provider name", () => {
  assertEquals(parseCurrentUser({ name: "User Name" }), "User Name");
});

Deno.test("parsePrimaryOrg keeps provider org metadata", () => {
  const org = parsePrimaryOrg([
    { id: "org_123", name: "Acme", primaryEmail: "owner@example.com" },
  ]);
  assertEquals(org, {
    id: "org_123",
    name: "Acme",
    primaryEmail: "owner@example.com",
  });
});

Deno.test("parsePrimaryOrg returns null without a provider org", () => {
  assertEquals(parsePrimaryOrg({ id: "org_123" }), null);
});
