# Connectum Phase 1a-i — Source Connection & Discovery Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the server-side (Supabase Edge Functions) credential-storage and source-discovery layer so Connectum can connect a Supabase account (list its projects and tables), connect an Amplitude project (validate key+secret), and connect an Axiom account (validate token, list datasets) — all with secrets stored server-side in Vault and never exposed to the app.

**Architecture:** Each source gets a thin Edge Function (Deno/TS) that the macOS app will call. Business logic (request builders, response parsers, validation) lives in pure modules with `deno test` unit tests; the `index.ts` handlers do thin wiring (read the stored secret from Vault → call the source API → upsert a row). A shared `mgmt.ts` wraps the Supabase Management API and `vault.ts` reads/writes secrets via RPC. Discovery uses the Management API `database/query` endpoint (Database read scope) so no project API keys are needed.

**Tech Stack:** Supabase CLI 2.90 (local stack already running), Postgres + Vault, Deno 2.7 Edge Functions, Supabase Management API, Amplitude Export API, Axiom API. Builds on Phase 0 (schema, `vault_set`, `_shared/{cors,admin}.ts`, `oauth-supabase`).

**Prerequisites:** Phase 0 merged to `main`. Local stack up (`supabase start`). `.env.local` holds real credentials (SUPABASE_PAT, AMPLITUDE_API_KEY/SECRET_KEY/REGION, AXIOM_TOKEN). Start this work on a new branch: `git checkout -b phase1a-connections-backend`.

---

## File Structure

```
supabase/
├─ migrations/
│  └─ 0005_vault_get.sql              # vault_get RPC (read secret by name)
└─ functions/
   ├─ _shared/
   │  ├─ vault.ts                     # getSecret/setSecret via RPC
   │  ├─ mgmt.ts                      # Supabase Management API fetch wrapper
   │  └─ amplitude.ts                 # Amplitude host + export-probe URL builder
   │  └─ amplitude.test.ts
   │  └─ mgmt.test.ts
   ├─ supabase-list-projects/
   │  ├─ index.ts                     # GET stored token → /v1/projects
   │  └─ projects.test.ts             # parseProjects unit test
   │  └─ projects.ts                  # parseProjects
   ├─ supabase-list-tables/
   │  ├─ index.ts                     # POST /v1/projects/{ref}/database/query
   │  ├─ tables.ts                    # LIST_TABLES_SQL + parseTables
   │  └─ tables.test.ts
   ├─ amplitude-connect/
   │  ├─ index.ts                     # validate creds (export probe) → store → insert row
   │  └─ (uses _shared/amplitude.ts)
   └─ axiom-connect/
      ├─ index.ts                     # validate token (GET /datasets) → store → insert row + return datasets
      ├─ datasets.ts                  # parseDatasets
      └─ datasets.test.ts
scripts/
└─ seed_supabase_account.ts           # one-off: store .env.local PAT as a supabase_account (for live verify)
```

**Decomposition rationale:** Pure parser/builder modules (`projects.ts`, `tables.ts`, `datasets.ts`, `mgmt.ts`, `amplitude.ts`) are unit-tested without network. Handlers stay thin. `vault.ts`/`mgmt.ts` are shared so each source function is tiny.

**Credential model note:** A `supabase_account` row stores a token reference in Vault (`access_token_ref`). Phase 0's `oauth-supabase` writes OAuth tokens; for now (and for live verification) a PAT can be stored the same way. The discovery functions read whatever token is in the account's `access_token_ref` — they work for both OAuth tokens and PATs.

---

## Task 1: `vault_get` RPC + shared vault helper

**Files:**
- Create: `supabase/migrations/0005_vault_get.sql`
- Create: `supabase/functions/_shared/vault.ts`

- [ ] **Step 1: Write the migration**

`supabase/migrations/0005_vault_get.sql`:
```sql
-- Read a Vault secret by name (server-side use only).
create or replace function public.vault_get(secret_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare v text;
begin
  select decrypted_secret into v from vault.decrypted_secrets where name = secret_name;
  return v;
end $$;
revoke all on function public.vault_get(text) from public, anon, authenticated;
```

- [ ] **Step 2: Apply and verify**

Run: `supabase db reset`
Then: `supabase db query "select public.vault_set('t_demo','hello'); select public.vault_get('t_demo') as got;"`
Expected: output contains `"got": "hello"`.

- [ ] **Step 3: Write the shared vault helper**

`supabase/functions/_shared/vault.ts`:
```typescript
import { adminClient } from "./admin.ts";

// Server-side secret access via the SECURITY DEFINER RPCs.
export async function getSecret(name: string): Promise<string> {
  const db = adminClient();
  const { data, error } = await db.rpc("vault_get", { secret_name: name });
  if (error) throw error;
  if (data == null) throw new Error(`secret not found: ${name}`);
  return data as string;
}

export async function setSecret(name: string, value: string): Promise<void> {
  const db = adminClient();
  const { error } = await db.rpc("vault_set", { secret_name: name, secret_value: value });
  if (error) throw error;
}
```

- [ ] **Step 4: Type-check**

Run: `deno check supabase/functions/_shared/vault.ts`
Expected: `Check ...` with no errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0005_vault_get.sql supabase/functions/_shared/vault.ts
git commit -m "feat(functions): vault_get RPC + shared secret helper"
```

---

## Task 2: Shared Supabase Management API wrapper

**Files:**
- Create: `supabase/functions/_shared/mgmt.ts`
- Test: `supabase/functions/_shared/mgmt.test.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/_shared/mgmt.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { mgmtUrl, mgmtHeaders } from "./mgmt.ts";

Deno.test("mgmtUrl joins the base with a path", () => {
  assertEquals(mgmtUrl("/v1/projects"), "https://api.supabase.com/v1/projects");
  assertEquals(mgmtUrl("v1/projects"), "https://api.supabase.com/v1/projects");
});

Deno.test("mgmtHeaders sets bearer auth + json", () => {
  const h = mgmtHeaders("tok123");
  assertEquals(h["Authorization"], "Bearer tok123");
  assertEquals(h["Content-Type"], "application/json");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/mgmt.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/_shared/mgmt.ts`:
```typescript
const BASE = "https://api.supabase.com";

export function mgmtUrl(path: string): string {
  return `${BASE}/${path.replace(/^\//, "")}`;
}

export function mgmtHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

// Convenience GET returning parsed JSON; throws on non-2xx with body text.
export async function mgmtGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(mgmtUrl(path), { headers: mgmtHeaders(token) });
  if (!res.ok) throw new Error(`mgmt GET ${path} -> ${res.status}: ${await res.text()}`);
  return await res.json() as T;
}

// Convenience POST (used for the database/query endpoint).
export async function mgmtPost<T>(path: string, token: string, body: unknown): Promise<T> {
  const res = await fetch(mgmtUrl(path), { method: "POST", headers: mgmtHeaders(token), body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`mgmt POST ${path} -> ${res.status}: ${await res.text()}`);
  return await res.json() as T;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/_shared/mgmt.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/mgmt.ts supabase/functions/_shared/mgmt.test.ts
git commit -m "feat(functions): Supabase Management API helper"
```

---

## Task 3: Seed script — store the PAT as a supabase_account (for live verification)

**Files:**
- Create: `scripts/seed_supabase_account.ts`

This lets later tasks verify discovery against the real account without the OAuth app.

- [ ] **Step 1: Write the seed script**

`scripts/seed_supabase_account.ts`:
```typescript
// Run: deno run -A --env-file=.env.local scripts/seed_supabase_account.ts
// Stores the .env.local PAT into Vault and creates a supabase_account row whose
// access_token_ref points at it. Prints the account id. Idempotent-ish: always
// inserts a fresh row (fine for local dev). Requires the local stack running.
import { createClient } from "jsr:@supabase/supabase-js@2";

const pat = Deno.env.get("SUPABASE_PAT");
if (!pat) throw new Error("SUPABASE_PAT missing in .env.local");

// Local stack defaults (from `supabase status`). Override via env if needed.
const url = Deno.env.get("LOCAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("LOCAL_SERVICE_ROLE_KEY");
if (!serviceKey) throw new Error("Set LOCAL_SERVICE_ROLE_KEY (from `supabase status`) before running");

const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const ref = `supabase_pat_${crypto.randomUUID()}`;
const { error: vErr } = await db.rpc("vault_set", { secret_name: ref, secret_value: pat });
if (vErr) throw vErr;
const { data, error } = await db.from("supabase_account")
  .insert({ label: "PAT (dev)", access_token_ref: ref }).select("id").single();
if (error) throw error;
console.log("supabase_account id:", data.id);
console.log("token ref:", ref);
```

- [ ] **Step 2: Run it (live)**

Run:
```bash
export LOCAL_SERVICE_ROLE_KEY="$(supabase status -o env | grep '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '\"')"
deno run -A --env-file=.env.local scripts/seed_supabase_account.ts
```
Expected: prints a `supabase_account id:` UUID. Record it — Tasks 4 & 5 use it.

- [ ] **Step 3: Commit**

```bash
git add scripts/seed_supabase_account.ts
git commit -m "chore(scripts): seed a supabase_account from the dev PAT"
```

---

## Task 4: `supabase-list-projects` function

**Files:**
- Create: `supabase/functions/supabase-list-projects/projects.ts`
- Test: `supabase/functions/supabase-list-projects/projects.test.ts`
- Create: `supabase/functions/supabase-list-projects/index.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/supabase-list-projects/projects.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { parseProjects } from "./projects.ts";

Deno.test("parseProjects keeps id/name/region only", () => {
  const out = parseProjects([
    { id: "abc", name: "Proj A", region: "ap-northeast-2", organization_id: "o1" },
    { id: "def", name: "Proj B", region: "us-east-1", organization_id: "o1" },
  ]);
  assertEquals(out, [
    { ref: "abc", name: "Proj A", region: "ap-northeast-2" },
    { ref: "def", name: "Proj B", region: "us-east-1" },
  ]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/supabase-list-projects/projects.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the parser**

`supabase/functions/supabase-list-projects/projects.ts`:
```typescript
export interface ProjectOut { ref: string; name: string; region: string; }

export function parseProjects(raw: Array<{ id: string; name: string; region: string }>): ProjectOut[] {
  return raw.map((p) => ({ ref: p.id, name: p.name, region: p.region }));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/supabase-list-projects/projects.test.ts`
Expected: PASS (1 passed).

- [ ] **Step 5: Implement the handler**

`supabase/functions/supabase-list-projects/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import { parseProjects } from "./projects.ts";

// Body: { account_id }. Reads that supabase_account's token from Vault, lists projects.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.access_token_ref);
    const raw = await mgmtGet<Array<{ id: string; name: string; region: string }>>("/v1/projects", token);
    return new Response(JSON.stringify({ projects: parseProjects(raw) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 6: Live verify against the seeded account**

Run (terminal 1): `supabase functions serve supabase-list-projects --no-verify-jwt`
Run (terminal 2), substituting the account id from Task 3 and the anon key from `supabase status`:
```bash
ANON="$(supabase status -o env | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '\"')"
curl -s -X POST http://127.0.0.1:54321/functions/v1/supabase-list-projects \
  -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
  -d '{"account_id":"<ACCOUNT_ID_FROM_TASK_3>"}'
```
Expected: JSON `{"projects":[{"ref":"...","name":"...","region":"..."}, ...]}` with the real projects (e.g. 5 projects). Stop the serve process.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/supabase-list-projects
git commit -m "feat(functions): supabase-list-projects (Management API)"
```

---

## Task 5: `supabase-list-tables` function (Management database/query)

**Files:**
- Create: `supabase/functions/supabase-list-tables/tables.ts`
- Test: `supabase/functions/supabase-list-tables/tables.test.ts`
- Create: `supabase/functions/supabase-list-tables/index.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/supabase-list-tables/tables.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { LIST_TABLES_SQL, parseTables } from "./tables.ts";

Deno.test("LIST_TABLES_SQL targets base tables in user schemas", () => {
  // Sanity: excludes internal schemas and only base tables.
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/supabase-list-tables/tables.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/supabase-list-tables/tables.ts`:
```typescript
// Lists user base tables (excludes Postgres/Supabase internal schemas).
export const LIST_TABLES_SQL = `
  select table_schema, table_name
  from information_schema.tables
  where table_type = 'BASE TABLE'
    and table_schema not in ('pg_catalog','information_schema','auth','storage','vault',
                             'graphql','graphql_public','realtime','supabase_functions',
                             'supabase_migrations','extensions','pgsodium','pgsodium_masks','net')
  order by table_schema, table_name
`;

export interface TableOut { schema: string; table: string; }

export function parseTables(rows: Array<{ table_schema: string; table_name: string }>): TableOut[] {
  return rows.map((r) => ({ schema: r.table_schema, table: r.table_name }));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/supabase-list-tables/tables.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 5: Implement the handler**

`supabase/functions/supabase-list-tables/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtPost } from "../_shared/mgmt.ts";
import { LIST_TABLES_SQL, parseTables } from "./tables.ts";

// Body: { account_id, project_ref }. Runs a read-only schema query via the
// Management API database/query endpoint (Database read scope).
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id, project_ref } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.access_token_ref);
    const rows = await mgmtPost<Array<{ table_schema: string; table_name: string }>>(
      `/v1/projects/${project_ref}/database/query`, token, { query: LIST_TABLES_SQL });
    return new Response(JSON.stringify({ tables: parseTables(rows) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 6: Live verify**

Run (terminal 1): `supabase functions serve supabase-list-tables --no-verify-jwt`
Run (terminal 2), using a real `project_ref` from Task 4's output (e.g. one of the listed projects) and the Task 3 account id:
```bash
ANON="$(supabase status -o env | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '\"')"
curl -s -X POST http://127.0.0.1:54321/functions/v1/supabase-list-tables \
  -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
  -d '{"account_id":"<ACCOUNT_ID>","project_ref":"<PROJECT_REF>"}'
```
Expected: JSON `{"tables":[{"schema":"public","table":"..."}, ...]}`. **If this returns a 403/permission error**, the OAuth/PAT token lacks the Database read scope — note it; the dashboard OAuth app must grant Database: Read-only (already set per setup). A PAT has full access so it should work. Stop the serve process.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/supabase-list-tables
git commit -m "feat(functions): supabase-list-tables via Management database/query"
```

---

## Task 6: `axiom-connect` function (validate + store + list datasets)

**Files:**
- Create: `supabase/functions/axiom-connect/datasets.ts`
- Test: `supabase/functions/axiom-connect/datasets.test.ts`
- Create: `supabase/functions/axiom-connect/index.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/axiom-connect/datasets.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { parseDatasets } from "./datasets.ts";

Deno.test("parseDatasets keeps dataset names", () => {
  const out = parseDatasets([{ name: "prod-logs", id: "x" }, { name: "audit", id: "y" }]);
  assertEquals(out, ["prod-logs", "audit"]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/axiom-connect/datasets.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the parser**

`supabase/functions/axiom-connect/datasets.ts`:
```typescript
export function parseDatasets(raw: Array<{ name: string }>): string[] {
  return raw.map((d) => d.name);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/axiom-connect/datasets.test.ts`
Expected: PASS (1 passed).

- [ ] **Step 5: Implement the handler**

`supabase/functions/axiom-connect/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { parseDatasets } from "./datasets.ts";

// Body: { token, label }. Validates the Axiom token by listing datasets, stores
// the token in Vault, creates an axiom_account row, returns the dataset names.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { token, label } = await req.json();
    const res = await fetch("https://api.axiom.co/v1/datasets", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ error: `axiom validation failed: ${res.status}` }),
        { status: 400, headers: corsHeaders });
    }
    const datasets = parseDatasets(await res.json());

    const ref = `axiom_token_${crypto.randomUUID()}`;
    await setSecret(ref, token);
    const db = adminClient();
    const { data, error } = await db.from("axiom_account")
      .insert({ label: label ?? "Axiom", api_token_ref: ref }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id, datasets }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 6: Live verify**

Run (terminal 1): `supabase functions serve axiom-connect --no-verify-jwt`
Run (terminal 2), passing the real token from `.env.local`:
```bash
ANON="$(supabase status -o env | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '\"')"
TOKEN="$(grep '^AXIOM_TOKEN=' .env.local | cut -d= -f2- | tr -d '\"')"
curl -s -X POST http://127.0.0.1:54321/functions/v1/axiom-connect \
  -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
  -d "{\"token\":\"$TOKEN\",\"label\":\"Axiom dev\"}"
```
Expected: JSON `{"account_id":"...","datasets":["archy-production","archy-v2-prod-logs","axiom-audit"]}`. Stop the serve process.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/axiom-connect
git commit -m "feat(functions): axiom-connect (validate + store + list datasets)"
```

---

## Task 7: `amplitude-connect` function (validate + store)

**Files:**
- Create: `supabase/functions/_shared/amplitude.ts`
- Test: `supabase/functions/_shared/amplitude.test.ts`
- Create: `supabase/functions/amplitude-connect/index.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/_shared/amplitude.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { amplitudeHost, exportProbeUrl, basicAuth } from "./amplitude.ts";

Deno.test("amplitudeHost picks EU vs US", () => {
  assertEquals(amplitudeHost("eu"), "analytics.eu.amplitude.com");
  assertEquals(amplitudeHost("us"), "amplitude.com");
  assertEquals(amplitudeHost(undefined), "amplitude.com");
});

Deno.test("exportProbeUrl builds a 1-hour window with YYYYMMDDTHH stamps", () => {
  const url = exportProbeUrl("us", new Date("2026-06-01T05:30:00Z"));
  // end = 05, start = 04 (one hour earlier, hour-truncated)
  assertEquals(url, "https://amplitude.com/api/2/export?start=2026060104&end=2026060105");
});

Deno.test("basicAuth base64-encodes key:secret", () => {
  assertEquals(basicAuth("k", "s"), "Basic " + btoa("k:s"));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/amplitude.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/_shared/amplitude.ts`:
```typescript
export function amplitudeHost(region?: string): string {
  return (region ?? "us").toLowerCase() === "eu" ? "analytics.eu.amplitude.com" : "amplitude.com";
}

function stampHour(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}${p(d.getUTCHours())}`;
}

// A cheap 1-hour Export probe used to validate credentials. 200 or 404 = valid creds.
export function exportProbeUrl(region: string | undefined, now: Date = new Date()): string {
  const end = stampHour(now);
  const start = stampHour(new Date(now.getTime() - 3600 * 1000));
  return `https://${amplitudeHost(region)}/api/2/export?start=${start}&end=${end}`;
}

export function basicAuth(key: string, secret: string): string {
  return "Basic " + btoa(`${key}:${secret}`);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/_shared/amplitude.test.ts`
Expected: PASS (3 passed).

- [ ] **Step 5: Implement the handler**

`supabase/functions/amplitude-connect/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { exportProbeUrl, basicAuth } from "../_shared/amplitude.ts";

// Body: { api_key, secret_key, region, label }. Validates via a 1-hour Export probe
// (200 or 404 = valid), stores both secrets in Vault, creates an amplitude_account row.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { api_key, secret_key, region, label } = await req.json();
    const res = await fetch(exportProbeUrl(region), { headers: { Authorization: basicAuth(api_key, secret_key) } });
    await res.body?.cancel();
    if (res.status !== 200 && res.status !== 404) {
      return new Response(JSON.stringify({ error: `amplitude validation failed: ${res.status}` }),
        { status: 400, headers: corsHeaders });
    }
    const keyRef = `amplitude_key_${crypto.randomUUID()}`;
    const secretRef = `amplitude_secret_${crypto.randomUUID()}`;
    await setSecret(keyRef, api_key);
    await setSecret(secretRef, secret_key);
    const db = adminClient();
    const { data, error } = await db.from("amplitude_account").insert({
      label: label ?? "Amplitude", region: (region ?? "us").toLowerCase(),
      api_key_ref: keyRef, secret_key_ref: secretRef,
    }).select("id").single();
    if (error) throw error;
    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 6: Live verify**

Run (terminal 1): `supabase functions serve amplitude-connect --no-verify-jwt`
Run (terminal 2):
```bash
ANON="$(supabase status -o env | grep '^ANON_KEY=' | cut -d= -f2- | tr -d '\"')"
K="$(grep '^AMPLITUDE_API_KEY=' .env.local | cut -d= -f2- | tr -d '\"')"
S="$(grep '^AMPLITUDE_SECRET_KEY=' .env.local | cut -d= -f2- | tr -d '\"')"
curl -s -X POST http://127.0.0.1:54321/functions/v1/amplitude-connect \
  -H "Authorization: Bearer $ANON" -H 'Content-Type: application/json' \
  -d "{\"api_key\":\"$K\",\"secret_key\":\"$S\",\"region\":\"us\",\"label\":\"Amplitude dev\"}"
```
Expected: JSON `{"account_id":"..."}` (HTTP 200). Stop the serve process.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/amplitude.ts supabase/functions/_shared/amplitude.test.ts supabase/functions/amplitude-connect
git commit -m "feat(functions): amplitude-connect (validate + store credentials)"
```

---

## Done — Definition of Done

- [ ] `supabase db reset` applies 0005; `vault_get` round-trips a secret.
- [ ] `deno test supabase/functions/` — all unit tests pass (Phase 0's 7 + mgmt 2 + projects 1 + tables 2 + datasets 1 + amplitude 3 = 16).
- [ ] Live verify: `supabase-list-projects` returns the real projects; `supabase-list-tables` returns a project's tables; `axiom-connect` returns the 3 datasets; `amplitude-connect` returns 200 + an account id. Results (incl. any 403 on list-tables) recorded in commits.
- [ ] No source credentials are ever returned to the caller; only refs/ids and discovery results.

---

## Self-Review Notes (author)

- **Spec coverage:** Implements spec §6.1 (list projects/tables via Management API), §6.2 (Amplitude connect/validate + credential storage), §6.3 (Axiom connect + dataset listing), §11 (all secrets in Vault, server-only). **Deferred (by design):** the OAuth *authorize/redirect* UI + loopback listener (app side, next plan), Amplitude live-event enumeration + actual event/table ingestion (ingestion plan), Vertex/operational features (later plans). The `oauth-supabase` token-exchange already exists from Phase 0; this plan reads whatever token an account holds (OAuth or PAT), so it is connection-method-agnostic.
- **Placeholders:** None. The only runtime substitutions are real ids/keys the engineer pastes from `supabase status` / Task 3 output / `.env.local`, all explicitly shown.
- **Type consistency:** `getSecret`/`setSecret` signatures match across `vault.ts` and all handlers. `mgmtGet`/`mgmtPost` used consistently. `parseProjects`→`{ref,name,region}`, `parseTables`→`{schema,table}`, `parseDatasets`→`string[]` match their tests and handlers. All handlers read `access_token_ref`/`api_token_ref`/`api_key_ref`/`secret_key_ref` exactly as defined in the Phase 0 `0001_core_schema.sql`.
