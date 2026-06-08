import { assert, assertEquals } from "jsr:@std/assert";
import { runTool, TOOL_DEFS } from "./tools.ts";

// Minimal fake of the PostgREST builder chain used by the tools. Every method
// returns the same thenable builder; `then` resolves to { data, count }.
// deno-lint-ignore no-explicit-any
function fakeDb(capture: { table?: string; eqs: [string, unknown][] }, rows: unknown[]): any {
  const b: any = {
    _rows: rows,
    select() { return b; },
    eq(col: string, val: unknown) { capture.eqs.push([col, val]); return b; },
    neq() { return b; },
    gte() { return b; },
    order() { return b; },
    limit() { return b; },
    ilike() { return b; },
    or() { return b; },
    then(res: (v: { data: unknown[]; count: number }) => void) {
      res({ data: b._rows, count: b._rows.length });
    },
  };
  return { from(t: string) { capture.table = t; return b; } };
}

Deno.test("tool defs expose the five read-only tools", () => {
  const names = TOOL_DEFS.map((t) => t.name).sort();
  assertEquals(names, [
    "get_metrics",
    "get_service_overview",
    "get_user_detail",
    "get_user_events",
    "search_users",
  ]);
});

Deno.test("search_users scopes by service_id", async () => {
  const cap = { eqs: [] as [string, unknown][] };
  const db = fakeDb(cap, [{
    id: "u1",
    email: "a@b.com",
    display_name: null,
    contact_status: "new",
    ai_summary: null,
  }]);
  const out = await runTool(db, "svc-1", "search_users", { limit: 10 });
  assert(cap.eqs.some(([c, v]) => c === "service_id" && v === "svc-1"));
  assert(out.includes("a@b.com"));
});

Deno.test("get_user_detail scopes by service_id and id", async () => {
  const cap = { eqs: [] as [string, unknown][] };
  const db = fakeDb(cap, [{
    id: "u1",
    email: "a@b.com",
    supabase_profile: {},
    amplitude_profile: {},
    ai_summary: "s",
  }]);
  await runTool(db, "svc-1", "get_user_detail", { crm_user_id: "u1" });
  assert(cap.eqs.some(([c, v]) => c === "service_id" && v === "svc-1"));
  assert(cap.eqs.some(([c, v]) => c === "id" && v === "u1"));
});
