import { assertEquals } from "jsr:@std/assert";
import { quoteIdent, quoteLiteral, buildSelectSQL } from "./sql.ts";

Deno.test("quoteIdent double-quotes and escapes", () => {
  assertEquals(quoteIdent("users"), '"users"');
  assertEquals(quoteIdent('we"ird'), '"we""ird"');
});
Deno.test("quoteLiteral single-quotes and escapes", () => {
  assertEquals(quoteLiteral("a'b"), "'a''b'");
});
Deno.test("buildSelectSQL without cursor value omits WHERE", () => {
  const sql = buildSelectSQL({ schema: "public", table: "profiles", cursorColumn: "updated_at", limit: 500 });
  assertEquals(sql, 'select * from "public"."profiles" order by "updated_at" asc limit 500');
});
Deno.test("buildSelectSQL with cursor value adds WHERE >", () => {
  const sql = buildSelectSQL({ schema: "public", table: "profiles", cursorColumn: "updated_at", cursorValue: "2026-06-01T00:00:00Z", limit: 500 });
  assertEquals(sql, `select * from "public"."profiles" where "updated_at" > '2026-06-01T00:00:00Z' order by "updated_at" asc limit 500`);
});
