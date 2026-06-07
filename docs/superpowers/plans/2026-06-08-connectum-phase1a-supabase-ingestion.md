# Connectum Phase 1a-ii — Supabase Table Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync rows from a service's selected Supabase tables into Connectum's operational DB — the designated *user table* into `crm_user`, other selected tables into `mirrored_row` — incrementally (via a cursor column) and idempotently (upsert), using the Management API `database/query` endpoint and the account token already stored in Vault.

**Architecture:** A new `supabase-sync-tables` Edge Function takes a `service_id`, loads the service's `service_table` configs + the account token, and for each table reads new rows (cursor-filtered SELECT via Management `database/query`), maps them with the table's `column_map`, and upserts into `crm_user` (role `user_table`) or `mirrored_row` (role `related`), then advances the per-table `sync_cursor`. Pure SQL-builder/row-mapper/cursor modules are unit-tested; the handler is thin. A seed script creates a real service + table config for live verification.

**Tech Stack:** Deno 2.7 Edge Functions, Supabase Management API `database/query`, supabase-js upsert. Builds on Phase 0 schema (`crm_user`, `mirrored_row`, `service`, `service_table`, `sync_cursor`, `sync_run`) and Plan 2 (`_shared/{mgmt,vault,admin}.ts`, a seeded `supabase_account` with a working token).

**Prerequisites:** Phase 0 + Plan 2 merged to `main`. Local stack running. A `supabase_account` row exists (re-run `scripts/seed_supabase_account.ts` if the DB was reset). New branch: `git checkout -b phase1a-supabase-ingestion`.

---

## File Structure

```
supabase/functions/
├─ _shared/
│  ├─ sql.ts                 # quoteIdent, quoteLiteral, buildSelectSQL
│  └─ sql.test.ts
└─ supabase-sync-tables/
   ├─ map.ts                 # rowToCrmUser, rowToMirroredRow, maxCursor
   ├─ map.test.ts
   └─ index.ts               # orchestrates one service's table sync
scripts/
└─ seed_service.ts           # create a service + service_table rows for live verify
```

**Decomposition rationale:** SQL string construction and row→record mapping are pure and the riskiest correctness surfaces, so they get dedicated tested modules. The handler only wires DB reads/writes.

---

## Task 1: SQL builder module

**Files:**
- Create: `supabase/functions/_shared/sql.ts`
- Test: `supabase/functions/_shared/sql.test.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/_shared/sql.test.ts`:
```typescript
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
  assertEquals(sql,
    'select * from "public"."profiles" order by "updated_at" asc limit 500');
});

Deno.test("buildSelectSQL with cursor value adds WHERE >", () => {
  const sql = buildSelectSQL({ schema: "public", table: "profiles", cursorColumn: "updated_at", cursorValue: "2026-06-01T00:00:00Z", limit: 500 });
  assertEquals(sql,
    `select * from "public"."profiles" where "updated_at" > '2026-06-01T00:00:00Z' order by "updated_at" asc limit 500`);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/sql.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/_shared/sql.ts`:
```typescript
export function quoteIdent(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

export function quoteLiteral(value: string): string {
  return `'${value.replace(/'/g, "''")}'`;
}

export interface SelectArgs {
  schema: string; table: string; cursorColumn: string; cursorValue?: string; limit: number;
}

// Incremental, ordered SELECT. cursorValue (when present) filters strictly greater
// than the last-seen value so re-runs only pull new/updated rows.
export function buildSelectSQL(a: SelectArgs): string {
  const tbl = `${quoteIdent(a.schema)}.${quoteIdent(a.table)}`;
  const col = quoteIdent(a.cursorColumn);
  const where = a.cursorValue != null ? ` where ${col} > ${quoteLiteral(a.cursorValue)}` : "";
  return `select * from ${tbl}${where} order by ${col} asc limit ${a.limit}`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/_shared/sql.test.ts`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/sql.ts supabase/functions/_shared/sql.test.ts
git commit -m "feat(functions): SQL builder for incremental table reads"
```

---

## Task 2: Row mapping module

**Files:**
- Create: `supabase/functions/supabase-sync-tables/map.ts`
- Test: `supabase/functions/supabase-sync-tables/map.test.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/supabase-sync-tables/map.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { rowToCrmUser, rowToMirroredRow, maxCursor } from "./map.ts";

Deno.test("rowToCrmUser pulls id/email per column_map and keeps full row as profile", () => {
  const out = rowToCrmUser(
    { id: "u1", email: "a@b.com", name: "Al", plan: "free" },
    { user_id: "id", email: "email" },
    "svc-1",
  );
  assertEquals(out, {
    service_id: "svc-1",
    source_user_id: "u1",
    email: "a@b.com",
    supabase_profile: { id: "u1", email: "a@b.com", name: "Al", plan: "free" },
  });
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/supabase-sync-tables/map.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/supabase-sync-tables/map.ts`:
```typescript
type Row = Record<string, unknown>;

export interface CrmUserUpsert {
  service_id: string; source_user_id: string; email: string | null; supabase_profile: Row;
}

export function rowToCrmUser(row: Row, columnMap: Record<string, string>, serviceId: string): CrmUserUpsert {
  const idCol = columnMap.user_id ?? "id";
  const emailCol = columnMap.email;
  const email = emailCol != null && row[emailCol] != null ? String(row[emailCol]) : null;
  return {
    service_id: serviceId,
    source_user_id: String(row[idCol]),
    email,
    supabase_profile: row,
  };
}

export interface MirroredUpsert {
  service_id: string; service_table_id: string; source_pk: string; data: Row;
}

export function rowToMirroredRow(row: Row, columnMap: Record<string, string>, serviceTableId: string, serviceId: string): MirroredUpsert {
  const pkCol = columnMap.pk ?? "id";
  return { service_id: serviceId, service_table_id: serviceTableId, source_pk: String(row[pkCol]), data: row };
}

// Largest value of cursorColumn across rows (lexicographic on string form — works
// for ISO timestamps and monotonic ids). null when there are no rows.
export function maxCursor(rows: Row[], cursorColumn: string): string | null {
  let max: string | null = null;
  for (const r of rows) {
    const v = r[cursorColumn];
    if (v == null) continue;
    const s = String(v);
    if (max == null || s > max) max = s;
  }
  return max;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/supabase-sync-tables/map.test.ts`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/supabase-sync-tables/map.ts supabase/functions/supabase-sync-tables/map.test.ts
git commit -m "feat(functions): row mappers + cursor advance for table ingestion"
```

---

## Task 3: `supabase-sync-tables` handler

**Files:**
- Create: `supabase/functions/supabase-sync-tables/index.ts`

- [ ] **Step 1: Implement the handler (thin wiring over the tested modules)**

`supabase/functions/supabase-sync-tables/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtPost } from "../_shared/mgmt.ts";
import { buildSelectSQL } from "../_shared/sql.ts";
import { rowToCrmUser, rowToMirroredRow, maxCursor } from "./map.ts";

const PAGE = 500;

// Body: { service_id }. Syncs every configured service_table for the service.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { service_id } = await req.json().catch(() => ({ service_id: undefined }));
  const { data: run } = await db.from("sync_run")
    .insert({ service_id, source: "supabase", status: "running" }).select("id").single();
  const stats: Record<string, number> = {};
  try {
    const { data: svc, error: svcErr } = await db.from("service")
      .select("id, supabase_account_id, supabase_project_ref").eq("id", service_id).single();
    if (svcErr) throw svcErr;
    const { data: acct } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", svc.supabase_account_id).single();
    const token = await getSecret(acct!.access_token_ref);
    const { data: tables } = await db.from("service_table").select("*").eq("service_id", service_id);

    for (const t of tables ?? []) {
      const scopeKey = `table:${t.source_schema}.${t.source_table}`;
      const { data: cur } = await db.from("sync_cursor")
        .select("cursor_value").eq("service_id", service_id).eq("source", "supabase").eq("scope_key", scopeKey).maybeSingle();
      const sql = buildSelectSQL({
        schema: t.source_schema, table: t.source_table, cursorColumn: t.cursor_column ?? "updated_at",
        cursorValue: cur?.cursor_value ?? undefined, limit: PAGE,
      });
      const rows = await mgmtPost<Record<string, unknown>[]>(
        `/v1/projects/${svc.supabase_project_ref}/database/query`, token, { query: sql });

      if (t.role === "user_table") {
        const ups = rows.map((r) => rowToCrmUser(r, t.column_map ?? {}, service_id));
        if (ups.length) {
          const { error } = await db.from("crm_user").upsert(ups, { onConflict: "service_id,source_user_id" });
          if (error) throw error;
        }
      } else {
        const ups = rows.map((r) => rowToMirroredRow(r, t.column_map ?? {}, t.id, service_id));
        if (ups.length) {
          const { error } = await db.from("mirrored_row").upsert(ups, { onConflict: "service_table_id,source_pk" });
          if (error) throw error;
        }
      }
      stats[scopeKey] = (stats[scopeKey] ?? 0) + rows.length;

      const newCursor = maxCursor(rows, t.cursor_column ?? "updated_at");
      if (newCursor != null) {
        await db.from("sync_cursor").upsert(
          { service_id, source: "supabase", scope_key: scopeKey, cursor_value: newCursor, updated_at: new Date().toISOString() },
          { onConflict: "service_id,source,scope_key" });
      }
    }

    await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, stats }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e), stats }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/supabase-sync-tables/index.ts`
Expected: `Check ...` no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/supabase-sync-tables/index.ts
git commit -m "feat(functions): supabase-sync-tables orchestrator"
```

---

## Task 4: Service seed script (for live verification)

**Files:**
- Create: `scripts/seed_service.ts`

- [ ] **Step 1: Write the seed script**

`scripts/seed_service.ts`:
```typescript
// Run: LOCAL_SERVICE_ROLE_KEY=... deno run -A scripts/seed_service.ts <account_id> <project_ref> <schema.table> <role> <user_id_col> [email_col]
// Creates a `service` (linked to the supabase_account) and one `service_table`.
// Prints the service id. Example:
//   deno run -A scripts/seed_service.ts <acct> ydotomyiabchrdhytynr public.courses related id
import { createClient } from "jsr:@supabase/supabase-js@2";

const [accountId, projectRef, schemaTable, role, idCol, emailCol] = Deno.args;
if (!accountId || !projectRef || !schemaTable || !role || !idCol) {
  throw new Error("usage: <account_id> <project_ref> <schema.table> <role:user_table|related> <user_id_col> [email_col]");
}
const [schema, table] = schemaTable.split(".");
const url = Deno.env.get("LOCAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("LOCAL_SERVICE_ROLE_KEY");
if (!serviceKey) throw new Error("Set LOCAL_SERVICE_ROLE_KEY (from `supabase status`)");

const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const { data: svc, error: svcErr } = await db.from("service").insert({
  name: `${projectRef} (dev)`, supabase_account_id: accountId, supabase_project_ref: projectRef,
}).select("id").single();
if (svcErr) throw svcErr;
const columnMap = role === "user_table"
  ? { user_id: idCol, ...(emailCol ? { email: emailCol } : {}) }
  : { pk: idCol };
const { error: stErr } = await db.from("service_table").insert({
  service_id: svc.id, source_schema: schema, source_table: table, role, column_map: columnMap, cursor_column: "created_at",
});
if (stErr) throw stErr;
console.log("service id:", svc.id);
```

- [ ] **Step 2: Live-verify the full ingestion path**

First inspect a real project's tables + a cursor column. Using the `supabase_account` id (re-seed via `scripts/seed_supabase_account.ts` if needed) and a real *active* project ref (e.g. Archy `ydotomyiabchrdhytynr`), list tables via the Plan 2 function to choose a table and confirm it has a `created_at` column (or adjust the seed's `cursor_column`).

Then seed a service and run the sync:
```bash
export LOCAL_SERVICE_ROLE_KEY="$(supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '\"')"
# Re-seed account if DB was reset:
deno run -A --env-file=.env.local scripts/seed_supabase_account.ts   # note the printed account id
# Seed a service + one related table (pick a real table that has a created_at column):
deno run -A scripts/seed_service.ts <ACCOUNT_ID> ydotomyiabchrdhytynr public.<TABLE> related id
# Serve + invoke:
supabase functions serve supabase-sync-tables --no-verify-jwt > /tmp/synctbl.log 2>&1 &
PID=$!
ANON="$(supabase status -o env | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '\"')"
curl -s --retry 40 --retry-connrefused --retry-delay 1 --max-time 90 -X POST http://127.0.0.1:54321/functions/v1/supabase-sync-tables \
  -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' -d '{"service_id":"<SERVICE_ID>"}'
echo ""
kill $PID 2>/dev/null; wait $PID 2>/dev/null
# Verify rows landed + cursor advanced:
supabase db query "select count(*) as mirrored from mirrored_row;"
supabase db query "select source, status, stats from sync_run order by started_at desc limit 1;"
supabase db query "select scope_key, cursor_value from sync_cursor;"
```
Expected: the curl returns `{"run_id":"...","stats":{"table:public.<TABLE>": N}}` with N>0; `mirrored_row` count = N; `sync_run` shows `success`; `sync_cursor` has a value. **If the chosen project is paused** it returns HTTP 544 — pick an active project. To exercise the `user_table` path, repeat the seed with `role=user_table` against a table whose id column equals the Amplitude `user_id` (this populates `crm_user`).

- [ ] **Step 3: Commit**

```bash
git add scripts/seed_service.ts
git commit -m "chore(scripts): seed a service + service_table for ingestion verify"
```

---

## Done — Definition of Done

- [ ] `deno test supabase/functions/` — all pass (Plan 2's 16 + sql 4 + map 5 = 25).
- [ ] `deno check supabase/functions/supabase-sync-tables/index.ts` — no type errors.
- [ ] Live: against a real active project, `supabase-sync-tables` upserts rows into `mirrored_row` (and/or `crm_user`), writes a `success` sync_run with per-table counts, and advances `sync_cursor`. A second run with no new rows returns 0 new and does not duplicate (idempotent upsert).
- [ ] Results recorded in commits.

---

## Self-Review Notes (author)

- **Spec coverage:** Implements spec §4 step 3 (Supabase source → `crm_user` user table + `mirrored_row` others) and §7 (incremental via `sync_cursor`, `sync_run` lifecycle). Amplitude event ingestion (§4 step 4) is the next plan; Vertex/operational UI later.
- **Placeholders:** None. Live-verify uses real ids/refs the engineer inspects/pastes (account id, project ref, table, service id), all explicitly shown.
- **Type consistency:** `buildSelectSQL(SelectArgs)`, `rowToCrmUser`/`rowToMirroredRow`/`maxCursor` signatures match tests and the handler. Upsert `onConflict` keys (`service_id,source_user_id` and `service_table_id,source_pk`) match the unique constraints in Phase 0 `0001_core_schema.sql`. `sync_cursor` onConflict (`service_id,source,scope_key`) matches its unique constraint. Reads `access_token_ref` from `supabase_account` and `column_map`/`cursor_column`/`role` from `service_table` exactly as defined.
- **Edge note:** `maxCursor` uses lexicographic string comparison — correct for ISO-8601 timestamps and zero-padded/UUIDv7-style ids; a service whose cursor column is a non-monotonic or non-lexically-ordered type would need a typed comparison (out of scope; `created_at`/`updated_at` are the configured defaults).
```
