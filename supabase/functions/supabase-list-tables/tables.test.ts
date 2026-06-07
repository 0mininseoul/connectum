import { assertEquals } from "jsr:@std/assert";
import { LIST_TABLES_SQL, parseTables } from "./tables.ts";

Deno.test("LIST_TABLES_SQL targets base tables in user schemas", () => {
  if (!LIST_TABLES_SQL.includes("information_schema.tables")) throw new Error("must query information_schema.tables");
  if (!LIST_TABLES_SQL.includes("BASE TABLE")) throw new Error("must filter to BASE TABLE");
  if (!LIST_TABLES_SQL.includes("pg_catalog")) throw new Error("must exclude system schemas");
});

Deno.test("parseTables flattens rows to schema.table entries", () => {
  const out = parseTables([
    { table_schema: "public", table_name: "users" },
    { table_schema: "public", table_name: "orders" },
  ]);
  assertEquals(out, [
    { schema: "public", table: "users" },
    { schema: "public", table: "orders" },
  ]);
});
