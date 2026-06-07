import { assertEquals } from "jsr:@std/assert";
import { rowToCrmUser, rowToMirroredRow, maxCursor } from "./map.ts";

Deno.test("rowToCrmUser pulls id/email per column_map and keeps full row as profile", () => {
  const out = rowToCrmUser({ id: "u1", email: "a@b.com", name: "Al", plan: "free" }, { user_id: "id", email: "email" }, "svc-1");
  assertEquals(out, { service_id: "svc-1", source_user_id: "u1", email: "a@b.com", supabase_profile: { id: "u1", email: "a@b.com", name: "Al", plan: "free" } });
});
Deno.test("rowToCrmUser stringifies numeric ids and tolerates missing email", () => {
  const out = rowToCrmUser({ id: 42 }, { user_id: "id" }, "svc-1");
  assertEquals(out.source_user_id, "42");
  assertEquals(out.email, null);
});
Deno.test("rowToMirroredRow uses pk column (default id)", () => {
  const out = rowToMirroredRow({ id: "r1", x: 1 }, {}, "st-1", "svc-1");
  assertEquals(out, { service_id: "svc-1", service_table_id: "st-1", source_pk: "r1", data: { id: "r1", x: 1 } });
});
Deno.test("maxCursor returns the largest cursor-column value as string", () => {
  const rows = [{ updated_at: "2026-06-01" }, { updated_at: "2026-06-03" }, { updated_at: "2026-06-02" }];
  assertEquals(maxCursor(rows, "updated_at"), "2026-06-03");
});
Deno.test("maxCursor returns null for empty input", () => {
  assertEquals(maxCursor([], "updated_at"), null);
});
