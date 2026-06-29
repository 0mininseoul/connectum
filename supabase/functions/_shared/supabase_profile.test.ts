import { assertEquals } from "jsr:@std/assert";
import { displayNameFromSupabaseProfile } from "./supabase_profile.ts";

Deno.test("displayNameFromSupabaseProfile prefers primary email", () => {
  assertEquals(
    displayNameFromSupabaseProfile({
      primary_email: "user@example.com",
      username: "user",
    }),
    "user@example.com",
  );
});

Deno.test("displayNameFromSupabaseProfile skips blank fields", () => {
  assertEquals(
    displayNameFromSupabaseProfile({
      primary_email: "  ",
      username: "youngmin",
    }),
    "youngmin",
  );
});

Deno.test("displayNameFromSupabaseProfile reads nested identity metadata", () => {
  assertEquals(
    displayNameFromSupabaseProfile({
      identities: [{ identity_data: { email: "nested@example.com" } }],
    }),
    "nested@example.com",
  );
});

Deno.test("displayNameFromSupabaseProfile returns null when no display field exists", () => {
  assertEquals(
    displayNameFromSupabaseProfile({
      gotrue_id: "00000000-0000-0000-0000-000000000000",
    }),
    null,
  );
});
