import { assert, assertAlmostEquals, assertEquals, assertThrows } from "jsr:@std/assert";
import { computeKPI, fieldExpr, validateSpec, valueText } from "./kpi_spec.ts";

Deno.test("fieldExpr maps direct + jsonb fields, rejects unknown", () => {
  assertEquals(fieldExpr("contact_status"), "contact_status");
  assertEquals(fieldExpr("profile.auth_provider"), "supabase_profile->>auth_provider");
  assertEquals(fieldExpr("amplitude.os"), "amplitude_profile->>os");
  assertThrows(() => fieldExpr("supabase_profile; drop table"));
  assertThrows(() => fieldExpr("profile.bad-key"));
});

Deno.test("validateSpec normalizes + rejects bad kind", () => {
  const s = validateSpec({ kind: "ratio", filter: { field: "profile.auth_provider", op: "eq", value: "kakao" } });
  assertEquals(s.kind, "ratio");
  assertEquals(s.unit, "percent");
  assertEquals(s.filter?.field, "profile.auth_provider");
  assertThrows(() => validateSpec({ kind: "median" }));
  assertThrows(() => validateSpec({ kind: "count", filter: { field: "evil.col", op: "eq" } }));
});

// deno-lint-ignore no-explicit-any
function fakeDb(counts: number[], capture: { filters: [string, unknown][] }): any {
  let i = 0;
  const make = () => {
    const b: any = {
      select() { return b; },
      eq(c: string, v: unknown) { capture.filters.push([c, v]); return b; },
      neq() { return b; },
      ilike(c: string, v: unknown) { capture.filters.push([c, v]); return b; },
      not() { return b; },
      then(res: (x: { count: number }) => void) { res({ count: counts[i++] ?? 0 }); },
    };
    return b;
  };
  return { from() { return make(); } };
}

Deno.test("computeKPI ratio: numerator/denominator over crm_user with mapped filter", async () => {
  const cap = { filters: [] as [string, unknown][] };
  const db = fakeDb([151, 359], cap);
  const out = await computeKPI(db, "svc-1", validateSpec({
    kind: "ratio",
    filter: { field: "profile.auth_provider", op: "eq", value: "kakao" },
    unit: "percent",
  }));
  assertEquals(out.numerator, 151);
  assertEquals(out.denominator, 359);
  assertAlmostEquals(out.value, 42.06, 0.1);
  assert(cap.filters.some(([c, v]) => c === "service_id" && v === "svc-1"));
  assert(cap.filters.some(([c, v]) => c === "supabase_profile->>auth_provider" && v === "kakao"));
});

Deno.test("computeKPI count returns the filtered count", async () => {
  const cap = { filters: [] as [string, unknown][] };
  const db = fakeDb([42], cap);
  const out = await computeKPI(db, "svc-1", validateSpec({
    kind: "count",
    filter: { field: "contact_status", op: "eq", value: "contacted" },
    unit: "count",
  }));
  assertEquals(out.value, 42);
});

Deno.test("valueText formats percent and count", () => {
  assertEquals(valueText(42.06, "percent"), "42.1%");
  assertEquals(valueText(151, "count"), "151");
});
