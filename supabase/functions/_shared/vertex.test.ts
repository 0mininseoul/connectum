import { assertEquals } from "jsr:@std/assert";
import { buildSummaryPrompt } from "./vertex.ts";

Deno.test("buildSummaryPrompt includes user, behavior, records and asks for 3 lines", () => {
  const p = buildSummaryPrompt(
    { email: "a@b.com", source_user_id: "u1", contact_status: "contacted",
      supabase_profile: { plan: "pro" }, amplitude_profile: { os: "Chrome", country: "KR" } },
    [{ event_type: "login", event_time: "2026-06-01T00:00:00Z" }],
    [{ channel: "email", body: "안녕", occurred_at: "2026-06-02" }],
  );
  if (!p.includes("a@b.com")) throw new Error("missing user");
  if (!p.includes("login")) throw new Error("missing event");
  if (!p.includes("안녕")) throw new Error("missing record");
  if (!p.includes("3줄")) throw new Error("must ask for 3 lines");
  assertEquals(typeof p, "string");
});
