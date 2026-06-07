# Connectum Phase 0 — Foundation & Validation Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Connectum monorepo, a local Supabase backend with the core schema, the Edge Functions runtime with a scheduled sync skeleton, prove all four external integrations (Supabase Management API, Amplitude Export, Axiom, Supabase OAuth token-exchange) work end-to-end with real free-plan credentials, and ship a native macOS SwiftUI app that logs in via Supabase Auth and renders the Raycast design tokens + Paperlogy + ko/en localization.

**Architecture:** Monorepo with three roots — `supabase/` (Postgres migrations + Deno Edge Functions + pg_cron schedule), `scripts/` (Deno validation spikes run with real credentials), and `apps/Connectum/` (XcodeGen-generated SwiftUI app). All external API calls and secrets live server-side in Edge Functions/Vault; the app is a thin authenticated client. De-risking is the priority: spikes confirm free-plan API access before Phase 1 builds on them.

**Tech Stack:** Supabase CLI 2.90, Postgres + pg_cron + pg_net + Vault, Deno 2.7 Edge Functions (TypeScript), Swift 6.3 / SwiftUI (macOS 14 target), XcodeGen 2.45, supabase-swift 2.x, String Catalogs, Paperlogy font.

---

## File Structure

```
connectum/
├─ .gitignore
├─ .env.example                       # documents required spike env vars (never commit real .env)
├─ README.md
├─ docs/superpowers/{specs,plans}/    # (specs/ already populated)
├─ supabase/
│  ├─ config.toml                     # supabase init output (edited)
│  ├─ migrations/
│  │  ├─ 0001_core_schema.sql         # all core tables + RLS
│  │  └─ 0002_cron_sync.sql           # pg_cron + pg_net schedule for sync function
│  └─ functions/
│     ├─ _shared/
│     │  ├─ cors.ts                   # CORS headers helper
│     │  ├─ admin.ts                  # service-role Supabase client factory
│     │  └─ chunk.ts                  # pure sync chunk-planner (unit tested)
│     ├─ _shared/chunk.test.ts        # deno test for chunk planner
│     ├─ health/index.ts              # GET health probe
│     ├─ health/health.test.ts        # deno test for health handler
│     ├─ oauth-supabase/index.ts      # OAuth code→token exchange (Supabase Management OAuth)
│     ├─ oauth-supabase/exchange.ts   # pure request-builder/response-parser (unit tested)
│     ├─ oauth-supabase/exchange.test.ts
│     ├─ sync/index.ts                # sync orchestrator skeleton (cursor + chunk loop + sync_run)
│     └─ sync/amplitude_map.ts        # pure Amplitude export-row → crm_user_event mapper (unit tested)
│     └─ sync/amplitude_map.test.ts
├─ scripts/
│  ├─ spike_supabase_mgmt.ts          # lists projects via Management API (PAT)
│  ├─ spike_amplitude_export.ts       # hits Export API, confirms gzip stream
│  └─ spike_axiom_datasets.ts         # lists datasets via Axiom API
└─ apps/Connectum/
   ├─ project.yml                     # XcodeGen project definition
   ├─ Connectum/
   │  ├─ ConnectumApp.swift           # @main app entry
   │  ├─ Info.plist                   # incl. ATSApplicationFontsPath = Fonts
   │  ├─ DesignSystem/
   │  │  ├─ Palette.swift             # Raycast surface ladder + text + accents
   │  │  ├─ Spacing.swift             # 8pt base scale + radius scale
   │  │  └─ Typography.swift          # Paperlogy fonts + type scale
   │  ├─ Localization/
   │  │  └─ Localizable.xcstrings     # ko (default) + en
   │  ├─ Supabase/
   │  │  ├─ SupabaseClientProvider.swift
   │  │  └─ AuthService.swift
   │  ├─ Features/Auth/
   │  │  ├─ AuthViewModel.swift
   │  │  └─ LoginView.swift
   │  ├─ App/RootView.swift           # routes login ↔ authenticated shell
   │  └─ Resources/Fonts/             # Paperlogy-*.ttf (user-provided)
   └─ ConnectumTests/
      ├─ DesignTokenTests.swift
      ├─ LocalizationTests.swift
      └─ AuthViewModelTests.swift
```

**Decomposition rationale:** Edge Function business logic is split into pure modules (`chunk.ts`, `exchange.ts`, `amplitude_map.ts`) that are unit-testable without network or DB, while `index.ts` files do thin wiring. The SwiftUI app splits design tokens, Supabase access, and the auth feature into focused files so each holds one responsibility.

**Credentials needed from the operator (you) for the spike tasks (5–7):** a Supabase **Personal Access Token** (Account → Access Tokens), one Amplitude project **API Key + Secret Key**, one Amplitude region (`us` or `eu`), and one Axiom **API token**. These go in a local `.env` (gitignored), never committed.

---

## Task 1: Repo scaffolding

**Files:**
- Create: `.gitignore`
- Create: `.env.example`
- Create: `README.md`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Secrets
.env
.env.*
!.env.example

# Supabase
supabase/.branches
supabase/.temp
supabase/.env

# Deno
deno.lock

# Xcode / Swift
apps/Connectum/Connectum.xcodeproj/
apps/Connectum/.build/
apps/Connectum/DerivedData/
**/xcuserdata/
.DS_Store

# Node (none expected, guard anyway)
node_modules/
```

- [ ] **Step 2: Create `.env.example`**

```bash
# Supabase Management API spike (Account > Access Tokens)
SUPABASE_PAT=sbp_xxx

# Amplitude Export API spike (Project > Settings > API Keys)
AMPLITUDE_API_KEY=xxx
AMPLITUDE_SECRET_KEY=xxx
AMPLITUDE_REGION=us   # us | eu

# Axiom datasets spike (Settings > API Tokens)
AXIOM_API_TOKEN=xaat-xxx
```

- [ ] **Step 3: Create `README.md`**

```markdown
# Connectum

Native macOS CRM tool. See `docs/superpowers/specs/2026-06-07-connectum-design.md`.

## Layout
- `supabase/` — Postgres migrations + Deno Edge Functions (sync, OAuth, AI)
- `scripts/` — Deno validation spikes (run with real credentials, see `.env.example`)
- `apps/Connectum/` — SwiftUI macOS app (generate Xcode project with `xcodegen generate`)

## Phase 0 quickstart
1. `cp .env.example .env` and fill in credentials.
2. `supabase start`
3. Run spikes: `deno run -A --env-file=.env scripts/spike_*.ts`
4. `cd apps/Connectum && xcodegen generate && open Connectum.xcodeproj`
```

- [ ] **Step 4: Verify and commit**

Run: `git status --porcelain`
Expected: shows `.gitignore`, `.env.example`, `README.md` as untracked.

```bash
git add .gitignore .env.example README.md
git commit -m "chore: repo scaffolding for Connectum"
```

---

## Task 2: Initialize local Supabase stack

**Files:**
- Create: `supabase/config.toml` (via CLI)

- [ ] **Step 1: Initialize Supabase**

Run: `supabase init`
Expected: creates `supabase/config.toml` and `supabase/` folders. If it prompts about generating VS Code settings, answer `N`.

- [ ] **Step 2: Start the local stack**

Run: `supabase start`
Expected: Docker pulls images, then prints `API URL`, `DB URL`, `anon key`, `service_role key`. Save these — later tasks use the local `API URL` (default `http://127.0.0.1:54321`) and `service_role key`.

- [ ] **Step 3: Verify status**

Run: `supabase status`
Expected: all services show `RUNNING` / lists keys.

- [ ] **Step 4: Commit**

```bash
git add supabase/config.toml
git commit -m "chore: init local supabase stack"
```

---

## Task 3: Core schema migration

**Files:**
- Create: `supabase/migrations/0001_core_schema.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 0001_core_schema.sql — Connectum core schema (shared-workspace MVP)
-- RLS: any authenticated team member may access everything (single workspace).

create extension if not exists "uuid-ossp";

-- Helper: shared-workspace access = authenticated
create or replace function public.is_team_member() returns boolean
language sql stable as $$ select auth.role() = 'authenticated' $$;

-- Team profile (1:1 with auth.users)
create table public.team_member (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Connected source accounts (token/secret bodies live in Vault; here we keep refs)
create table public.supabase_account (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  access_token_ref text,           -- vault secret name
  refresh_token_ref text,          -- vault secret name
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.amplitude_account (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  region text not null default 'us',
  api_key_ref text,
  secret_key_ref text,
  created_at timestamptz not null default now()
);
create table public.axiom_account (
  id uuid primary key default uuid_generate_v4(),
  label text not null,
  api_token_ref text,
  created_at timestamptz not null default now()
);

-- Services (1 service = 1 Supabase project)
create table public.service (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  supabase_account_id uuid references public.supabase_account(id) on delete set null,
  supabase_project_ref text,
  amplitude_account_id uuid references public.amplitude_account(id) on delete set null,
  axiom_account_id uuid references public.axiom_account(id) on delete set null,
  axiom_dataset text,
  join_key_config jsonb not null default '{"amplitude_user_id":"supabase.id"}'::jsonb,
  created_at timestamptz not null default now()
);
create table public.service_table (
  id uuid primary key default uuid_generate_v4(),
  service_id uuid not null references public.service(id) on delete cascade,
  source_schema text not null default 'public',
  source_table text not null,
  role text not null default 'related',          -- 'user_table' | 'related'
  column_map jsonb not null default '{}'::jsonb,  -- {user_id, email, ...}
  cursor_column text default 'updated_at'
);

-- Mirrored data
create table public.crm_user (
  id uuid primary key default uuid_generate_v4(),
  service_id uuid not null references public.service(id) on delete cascade,
  source_user_id text not null,
  email text,
  display_name text,
  supabase_profile jsonb not null default '{}'::jsonb,
  amplitude_profile jsonb not null default '{}'::jsonb,
  contact_status text not null default 'not_contacted', -- 'not_contacted' | 'contacted'
  custom_fields jsonb not null default '{}'::jsonb,
  ai_summary text,
  ai_summary_generated_at timestamptz,
  ai_summary_input_hash text,
  axiom_signals jsonb not null default '{}'::jsonb,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (service_id, source_user_id)
);
create table public.crm_user_event (
  id bigint generated by default as identity primary key,
  crm_user_id uuid not null references public.crm_user(id) on delete cascade,
  event_type text not null,
  event_time timestamptz not null,
  platform text, os text, browser text,
  props jsonb not null default '{}'::jsonb
);
create index on public.crm_user_event (crm_user_id, event_time desc);

create table public.mirrored_row (
  id uuid primary key default uuid_generate_v4(),
  service_id uuid not null references public.service(id) on delete cascade,
  service_table_id uuid not null references public.service_table(id) on delete cascade,
  source_pk text not null,
  data jsonb not null default '{}'::jsonb,
  linked_crm_user_id uuid references public.crm_user(id) on delete set null,
  unique (service_table_id, source_pk)
);

-- Manual operational layer
create table public.custom_field (
  id uuid primary key default uuid_generate_v4(),
  scope text not null default 'workspace',   -- 'workspace' | 'service'
  service_id uuid references public.service(id) on delete cascade,
  name text not null,
  type text not null,                        -- text|select|multi_select|date|checkbox|url|number|person
  options jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table public.page_block (
  id uuid primary key default uuid_generate_v4(),
  crm_user_id uuid not null references public.crm_user(id) on delete cascade,
  position double precision not null default 0,
  type text not null,                        -- channel_record|text|heading|image|divider|field_ref
  content jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.history_entry (
  id uuid primary key default uuid_generate_v4(),
  crm_user_id uuid not null references public.crm_user(id) on delete cascade,
  entry_date date not null,
  image_url text,
  memo text,
  position double precision not null default 0,
  created_at timestamptz not null default now()
);

-- Views / sync state
create table public.view (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  scope text not null default 'workspace',
  service_id uuid references public.service(id) on delete cascade,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create table public.sync_run (
  id uuid primary key default uuid_generate_v4(),
  service_id uuid references public.service(id) on delete cascade,
  source text not null,                      -- supabase|amplitude|axiom
  status text not null default 'running',    -- running|success|error
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  stats jsonb not null default '{}'::jsonb,
  error text
);
create table public.sync_cursor (
  id uuid primary key default uuid_generate_v4(),
  service_id uuid not null references public.service(id) on delete cascade,
  source text not null,
  scope_key text not null,
  cursor_value text,
  updated_at timestamptz not null default now(),
  unique (service_id, source, scope_key)
);

-- Enable RLS + shared-workspace policies on every public table
do $$
declare t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public'
      and tablename in (
        'team_member','supabase_account','amplitude_account','axiom_account',
        'service','service_table','crm_user','crm_user_event','mirrored_row',
        'custom_field','page_block','history_entry','view','sync_run','sync_cursor')
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format($p$create policy "team_all" on public.%I
      for all to authenticated using (public.is_team_member()) with check (public.is_team_member());$p$, t);
  end loop;
end $$;
```

- [ ] **Step 2: Apply the migration to local DB**

Run: `supabase db reset`
Expected: drops/recreates local DB, applies `0001_core_schema.sql`, ends with `Finished supabase db reset`. No SQL errors.

- [ ] **Step 3: Verify tables exist**

Run:
```bash
supabase db query "select count(*) as tables from pg_tables where schemaname='public' and tablename in ('crm_user','service','sync_run','page_block','history_entry');"
```
Expected: `tables = 5`.

- [ ] **Step 4: Verify RLS is on**

Run:
```bash
supabase db query "select count(*) as rls_on from pg_tables where schemaname='public' and rowsecurity = true;"
```
Expected: `rls_on >= 15`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0001_core_schema.sql
git commit -m "feat(db): core schema with shared-workspace RLS"
```

---

## Task 4: Edge Functions shared scaffold + health probe

**Files:**
- Create: `supabase/functions/_shared/cors.ts`
- Create: `supabase/functions/_shared/admin.ts`
- Create: `supabase/functions/health/index.ts`
- Test: `supabase/functions/health/health.test.ts`

- [ ] **Step 1: Write the failing test**

`supabase/functions/health/health.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { handleHealth } from "./index.ts";

Deno.test("health returns ok json", async () => {
  const res = await handleHealth();
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "ok");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/health/health.test.ts`
Expected: FAIL — `Module not found` / `handleHealth` is not exported.

- [ ] **Step 3: Write the shared helpers + health handler**

`supabase/functions/_shared/cors.ts`:
```typescript
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
```

`supabase/functions/_shared/admin.ts`:
```typescript
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Service-role client for trusted server-side work inside Edge Functions.
export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, serviceKey, { auth: { persistSession: false } });
}
```

`supabase/functions/health/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";

export function handleHealth(): Response {
  return new Response(JSON.stringify({ status: "ok", ts: new Date().toISOString() }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve((req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  return handleHealth();
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/health/health.test.ts`
Expected: PASS (1 passed).

- [ ] **Step 5: Verify it serves locally**

Run (in one terminal): `supabase functions serve health --no-verify-jwt`
Then: `curl -s http://127.0.0.1:54321/functions/v1/health`
Expected: `{"status":"ok","ts":"..."}`. Stop the serve process afterward.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/_shared supabase/functions/health
git commit -m "feat(functions): shared scaffold + health probe"
```

---

## Task 5: Spike — Supabase Management API (list projects)

**Files:**
- Create: `scripts/spike_supabase_mgmt.ts`

- [ ] **Step 1: Write the spike script**

```typescript
// Run: deno run -A --env-file=.env scripts/spike_supabase_mgmt.ts
// Proves a Personal Access Token can list projects (the data behind the
// "connect account → pick project" UX). OAuth replaces the PAT in Phase 1.
const pat = Deno.env.get("SUPABASE_PAT");
if (!pat) throw new Error("SUPABASE_PAT missing in .env");

const res = await fetch("https://api.supabase.com/v1/projects", {
  headers: { Authorization: `Bearer ${pat}` },
});
console.log("HTTP", res.status);
if (!res.ok) {
  console.error(await res.text());
  Deno.exit(1);
}
const projects = await res.json() as Array<{ id: string; name: string; region: string }>;
console.log(`projects: ${projects.length}`);
for (const p of projects.slice(0, 10)) console.log(` - ${p.name} (${p.id}, ${p.region})`);
```

- [ ] **Step 2: Run the spike with real credentials**

Run: `deno run -A --env-file=.env scripts/spike_supabase_mgmt.ts`
Expected: `HTTP 200` and a list of at least one project. **If non-200:** record the status/body in the commit message and stop — this gates Phase 1's Supabase connection.

- [ ] **Step 3: Commit**

```bash
git add scripts/spike_supabase_mgmt.ts
git commit -m "spike: verify Supabase Management API project listing"
```

---

## Task 6: Spike — Amplitude Export API (free-plan access)

**Files:**
- Create: `scripts/spike_amplitude_export.ts`

- [ ] **Step 1: Write the spike script**

```typescript
// Run: deno run -A --env-file=.env scripts/spike_amplitude_export.ts
// Confirms the free plan can hit the raw Export API. Export returns a gzip
// stream of events for a time window (Basic auth: apiKey:secretKey).
const key = Deno.env.get("AMPLITUDE_API_KEY");
const secret = Deno.env.get("AMPLITUDE_SECRET_KEY");
const region = (Deno.env.get("AMPLITUDE_REGION") ?? "us").toLowerCase();
if (!key || !secret) throw new Error("AMPLITUDE_API_KEY/SECRET_KEY missing in .env");

const host = region === "eu" ? "analytics.eu.amplitude.com" : "amplitude.com";
// Last 2 hours, Amplitude format YYYYMMDDTHH
const fmt = (d: Date) =>
  `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}${String(d.getUTCDate()).padStart(2, "0")}T${String(d.getUTCHours()).padStart(2, "0")}`;
const end = new Date();
const start = new Date(end.getTime() - 2 * 3600 * 1000);
const url = `https://${host}/api/2/export?start=${fmt(start)}&end=${fmt(end)}`;
const auth = btoa(`${key}:${secret}`);

const res = await fetch(url, { headers: { Authorization: `Basic ${auth}` } });
console.log("HTTP", res.status, "content-type:", res.headers.get("content-type"));
// 200 = data, 404 = no data in window (still proves access works), others = problem
if (res.status === 200 || res.status === 404) {
  console.log("Export API reachable on this plan ✅");
  await res.body?.cancel();
} else {
  console.error("Unexpected:", await res.text());
  Deno.exit(1);
}
```

- [ ] **Step 2: Run the spike**

Run: `deno run -A --env-file=.env scripts/spike_amplitude_export.ts`
Expected: `HTTP 200` or `HTTP 404` (404 = simply no events in the last 2h; access still proven). **Any 401/403 means the free plan blocks Export** — record it; Phase 1 falls back to the User Activity API per spec §6.2.

- [ ] **Step 3: Commit**

```bash
git add scripts/spike_amplitude_export.ts
git commit -m "spike: verify Amplitude Export API access on free plan"
```

---

## Task 7: Spike — Axiom datasets listing

**Files:**
- Create: `scripts/spike_axiom_datasets.ts`

- [ ] **Step 1: Write the spike script**

```typescript
// Run: deno run -A --env-file=.env scripts/spike_axiom_datasets.ts
// Proves "connect account → auto-load datasets" works (spec §6.3).
const token = Deno.env.get("AXIOM_API_TOKEN");
if (!token) throw new Error("AXIOM_API_TOKEN missing in .env");

const res = await fetch("https://api.axiom.co/v1/datasets", {
  headers: { Authorization: `Bearer ${token}` },
});
console.log("HTTP", res.status);
if (!res.ok) { console.error(await res.text()); Deno.exit(1); }
const datasets = await res.json() as Array<{ name: string }>;
console.log(`datasets: ${datasets.length}`);
for (const d of datasets) console.log(` - ${d.name}`);
```

- [ ] **Step 2: Run the spike**

Run: `deno run -A --env-file=.env scripts/spike_axiom_datasets.ts`
Expected: `HTTP 200` and a list of datasets (at least the one logs are written to).

- [ ] **Step 3: Commit**

```bash
git add scripts/spike_axiom_datasets.ts
git commit -m "spike: verify Axiom datasets listing"
```

---

## Task 8: OAuth token-exchange (Supabase Management OAuth) — pure logic + function

**Files:**
- Create: `supabase/functions/oauth-supabase/exchange.ts`
- Test: `supabase/functions/oauth-supabase/exchange.test.ts`
- Create: `supabase/functions/oauth-supabase/index.ts`

- [ ] **Step 1: Write the failing test for the pure builder/parser**

`supabase/functions/oauth-supabase/exchange.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { buildTokenRequest, parseTokenResponse } from "./exchange.ts";

Deno.test("buildTokenRequest encodes form body with auth code grant", () => {
  const req = buildTokenRequest({
    code: "abc",
    clientId: "cid",
    clientSecret: "csec",
    redirectUri: "connectum://oauth/callback",
  });
  assertEquals(req.url, "https://api.supabase.com/v1/oauth/token");
  assertEquals(req.headers["Content-Type"], "application/x-www-form-urlencoded");
  const params = new URLSearchParams(req.body);
  assertEquals(params.get("grant_type"), "authorization_code");
  assertEquals(params.get("code"), "abc");
  assertEquals(params.get("redirect_uri"), "connectum://oauth/callback");
});

Deno.test("parseTokenResponse extracts tokens + expiry", () => {
  const parsed = parseTokenResponse({
    access_token: "at", refresh_token: "rt", expires_in: 3600,
  });
  assertEquals(parsed.accessToken, "at");
  assertEquals(parsed.refreshToken, "rt");
  assertEquals(typeof parsed.expiresAt, "string");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/oauth-supabase/exchange.test.ts`
Expected: FAIL — module/exports not found.

- [ ] **Step 3: Implement the pure module**

`supabase/functions/oauth-supabase/exchange.ts`:
```typescript
export interface TokenRequestInput {
  code: string; clientId: string; clientSecret: string; redirectUri: string;
}
export interface BuiltRequest { url: string; headers: Record<string, string>; body: string; }

export function buildTokenRequest(i: TokenRequestInput): BuiltRequest {
  const body = new URLSearchParams({
    grant_type: "authorization_code",
    code: i.code,
    redirect_uri: i.redirectUri,
  }).toString();
  const basic = btoa(`${i.clientId}:${i.clientSecret}`);
  return {
    url: "https://api.supabase.com/v1/oauth/token",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basic}`,
    },
    body,
  };
}

export interface ParsedToken { accessToken: string; refreshToken: string; expiresAt: string; }
export function parseTokenResponse(raw: { access_token: string; refresh_token: string; expires_in: number }): ParsedToken {
  return {
    accessToken: raw.access_token,
    refreshToken: raw.refresh_token,
    expiresAt: new Date(Date.now() + raw.expires_in * 1000).toISOString(),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/oauth-supabase/exchange.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 5: Write the function wiring (uses the pure module)**

`supabase/functions/oauth-supabase/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { buildTokenRequest, parseTokenResponse } from "./exchange.ts";

// App sends { code, label } after ASWebAuthenticationSession returns the OAuth code.
// Client secret stays here (server). Tokens are written to Vault; only refs land in the table.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { code, label } = await req.json();
    const built = buildTokenRequest({
      code,
      clientId: Deno.env.get("SUPABASE_OAUTH_CLIENT_ID")!,
      clientSecret: Deno.env.get("SUPABASE_OAUTH_CLIENT_SECRET")!,
      redirectUri: "connectum://oauth/callback",
    });
    const tokenRes = await fetch(built.url, { method: "POST", headers: built.headers, body: built.body });
    if (!tokenRes.ok) {
      return new Response(JSON.stringify({ error: await tokenRes.text() }), { status: 502, headers: corsHeaders });
    }
    const tokens = parseTokenResponse(await tokenRes.json());

    const db = adminClient();
    const accessRef = `supabase_oauth_access_${crypto.randomUUID()}`;
    const refreshRef = `supabase_oauth_refresh_${crypto.randomUUID()}`;
    await db.rpc("vault_set", { secret_name: accessRef, secret_value: tokens.accessToken });
    await db.rpc("vault_set", { secret_name: refreshRef, secret_value: tokens.refreshToken });
    const { data, error } = await db.from("supabase_account").insert({
      label: label ?? "Supabase",
      access_token_ref: accessRef,
      refresh_token_ref: refreshRef,
      expires_at: tokens.expiresAt,
    }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
```

- [ ] **Step 6: Add the `vault_set` RPC used above**

Append to a new migration `supabase/migrations/0003_vault_rpc.sql`:
```sql
-- Wrapper so Edge Functions can store secrets in Vault by name.
create or replace function public.vault_set(secret_name text, secret_value text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  perform vault.create_secret(secret_value, secret_name);
end $$;
revoke all on function public.vault_set(text, text) from public, anon, authenticated;
```

Run: `supabase db reset`
Expected: applies cleanly (the `vault` schema exists in local Supabase by default).

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/oauth-supabase supabase/migrations/0003_vault_rpc.sql
git commit -m "feat(functions): supabase OAuth token-exchange + vault storage"
```

---

## Task 9: Sync orchestrator skeleton + chunk planner + Amplitude mapper

**Files:**
- Create: `supabase/functions/_shared/chunk.ts`
- Test: `supabase/functions/_shared/chunk.test.ts`
- Create: `supabase/functions/sync/amplitude_map.ts`
- Test: `supabase/functions/sync/amplitude_map.test.ts`
- Create: `supabase/functions/sync/index.ts`

- [ ] **Step 1: Write the failing test for the chunk planner**

`supabase/functions/_shared/chunk.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { planWindows } from "./chunk.ts";

Deno.test("planWindows splits a range into N-hour windows", () => {
  const wins = planWindows(new Date("2026-06-01T00:00:00Z"), new Date("2026-06-01T06:00:00Z"), 2);
  assertEquals(wins.length, 3);
  assertEquals(wins[0].start.toISOString(), "2026-06-01T00:00:00.000Z");
  assertEquals(wins[2].end.toISOString(), "2026-06-01T06:00:00.000Z");
});

Deno.test("planWindows clamps a partial final window to end", () => {
  const wins = planWindows(new Date("2026-06-01T00:00:00Z"), new Date("2026-06-01T05:00:00Z"), 2);
  assertEquals(wins.length, 3);
  assertEquals(wins[2].end.toISOString(), "2026-06-01T05:00:00.000Z");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/chunk.test.ts`
Expected: FAIL — `planWindows` not found.

- [ ] **Step 3: Implement the chunk planner**

`supabase/functions/_shared/chunk.ts`:
```typescript
export interface Window { start: Date; end: Date; }

// Split [start, end) into windows of `hours`, clamping the last to `end`.
// Used to keep each Edge Function invocation within its execution budget.
export function planWindows(start: Date, end: Date, hours: number): Window[] {
  const out: Window[] = [];
  const stepMs = hours * 3600 * 1000;
  let cur = start.getTime();
  const endMs = end.getTime();
  while (cur < endMs) {
    const next = Math.min(cur + stepMs, endMs);
    out.push({ start: new Date(cur), end: new Date(next) });
    cur = next;
  }
  return out;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/_shared/chunk.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 5: Write the failing test for the Amplitude mapper**

`supabase/functions/sync/amplitude_map.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { mapExportRow } from "./amplitude_map.ts";

Deno.test("mapExportRow keeps only matched users and normalizes fields", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const row = {
    user_id: "u1", event_type: "login", event_time: "2026-06-01 03:04:05.000000",
    os_name: "Mac OS X", device_family: "Mac", platform: "Web",
    event_properties: { plan: "free" },
  };
  const mapped = mapExportRow(row, matched);
  assertEquals(mapped?.crm_user_id, "crm-1");
  assertEquals(mapped?.event_type, "login");
  assertEquals(mapped?.os, "Mac OS X");
  assertEquals(mapped?.props.plan, "free");
});

Deno.test("mapExportRow drops unmatched users", () => {
  const mapped = mapExportRow({ user_id: "ghost", event_type: "x", event_time: "2026-06-01 00:00:00" }, new Map());
  assertEquals(mapped, null);
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `deno test supabase/functions/sync/amplitude_map.test.ts`
Expected: FAIL — `mapExportRow` not found.

- [ ] **Step 7: Implement the mapper**

`supabase/functions/sync/amplitude_map.ts`:
```typescript
export interface ExportRow {
  user_id?: string; event_type: string; event_time: string;
  os_name?: string; device_family?: string; platform?: string;
  event_properties?: Record<string, unknown>;
}
export interface MappedEvent {
  crm_user_id: string; event_type: string; event_time: string;
  platform: string | null; os: string | null; browser: string | null;
  props: Record<string, unknown>;
}

// matchedUsers: source_user_id -> crm_user.id. Spec: only registered/matched users.
export function mapExportRow(row: ExportRow, matchedUsers: Map<string, string>): MappedEvent | null {
  if (!row.user_id) return null;
  const crmId = matchedUsers.get(row.user_id);
  if (!crmId) return null;
  return {
    crm_user_id: crmId,
    event_type: row.event_type,
    event_time: row.event_time.replace(" ", "T") + "Z",
    platform: row.platform ?? null,
    os: row.os_name ?? null,
    browser: row.device_family ?? null,
    props: row.event_properties ?? {},
  };
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `deno test supabase/functions/sync/amplitude_map.test.ts`
Expected: PASS (2 passed).

- [ ] **Step 9: Write the orchestrator skeleton (thin wiring; no new logic to unit-test)**

`supabase/functions/sync/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { planWindows } from "../_shared/chunk.ts";

// Phase 0 skeleton: opens a sync_run, plans chunked windows from the cursor,
// records the plan, and closes the run. Phase 1 fills each window with real
// Supabase/Amplitude/Axiom fetches + upserts. Callable by pg_cron and the app.
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { data: run } = await db.from("sync_run")
    .insert({ source: "amplitude", status: "running" }).select("id").single();
  try {
    const since = new Date(Date.now() - 24 * 3600 * 1000); // Phase 1 reads sync_cursor instead
    const windows = planWindows(since, new Date(), 2);
    // Phase 1: for each window → fetch + map + upsert; advance sync_cursor.
    await db.from("sync_run").update({
      status: "success", finished_at: new Date().toISOString(),
      stats: { planned_windows: windows.length },
    }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, planned_windows: windows.length }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e) }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
});
```

- [ ] **Step 10: Verify the function serves and writes a sync_run**

Run (terminal 1): `supabase functions serve sync --no-verify-jwt`
Run (terminal 2): `curl -s -X POST http://127.0.0.1:54321/functions/v1/sync`
Expected: JSON `{"run_id":"...","planned_windows":12}`.
Then: `supabase db query "select source, status, stats from sync_run order by started_at desc limit 1;"`
Expected: one row `amplitude | success | {"planned_windows": 12}`. Stop the serve process.

- [ ] **Step 11: Commit**

```bash
git add supabase/functions/_shared/chunk.ts supabase/functions/_shared/chunk.test.ts supabase/functions/sync
git commit -m "feat(functions): sync skeleton with chunk planner + amplitude mapper"
```

---

## Task 10: Schedule the sync function with pg_cron + pg_net

**Files:**
- Create: `supabase/migrations/0004_cron_sync.sql`

- [ ] **Step 1: Write the schedule migration**

```sql
-- 0004_cron_sync.sql — run the sync Edge Function every 30 minutes.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Store the function URL + service key for pg_net to call. In hosted Supabase
-- these come from project settings; locally they target the local gateway.
-- Replace the placeholders at deploy time (documented in README deploy section).
do $$
begin
  perform cron.schedule(
    'connectum-sync',
    '*/30 * * * *',
    $cron$
      select net.http_post(
        url := current_setting('app.sync_function_url', true),
        headers := jsonb_build_object(
          'Content-Type','application/json',
          'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
        ),
        body := '{}'::jsonb
      );
    $cron$
  );
end $$;
```

- [ ] **Step 2: Set the local settings so the schedule is valid**

Run:
```bash
supabase db query "alter database postgres set app.sync_function_url = 'http://host.docker.internal:54321/functions/v1/sync'; alter database postgres set app.service_role_key = 'PLACEHOLDER_LOCAL_SERVICE_ROLE_KEY';"
```
Note: replace `PLACEHOLDER_LOCAL_SERVICE_ROLE_KEY` with the `service_role key` printed by `supabase status`.

- [ ] **Step 3: Apply and verify the cron job is registered**

Run: `supabase db reset`
Then: `supabase db query "select jobname, schedule, active from cron.job where jobname = 'connectum-sync';"`
Expected: one row `connectum-sync | */30 * * * * | t`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0004_cron_sync.sql
git commit -m "feat(db): schedule sync via pg_cron + pg_net"
```

---

## Task 11: SwiftUI app scaffold via XcodeGen

**Files:**
- Create: `apps/Connectum/project.yml`
- Create: `apps/Connectum/Connectum/ConnectumApp.swift`
- Create: `apps/Connectum/Connectum/Info.plist`
- Create: `apps/Connectum/Connectum/App/RootView.swift`

- [ ] **Step 1: Write the XcodeGen project definition**

`apps/Connectum/project.yml`:
```yaml
name: Connectum
options:
  bundleIdPrefix: com.connectum
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  Supabase:
    url: https://github.com/supabase/supabase-swift
    from: "2.0.0"
targets:
  Connectum:
    type: application
    platform: macOS
    sources: [Connectum]
    info:
      path: Connectum/Info.plist
      properties:
        CFBundleDisplayName: Connectum
        ATSApplicationFontsPath: Fonts
        LSMinimumSystemVersion: "14.0"
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.connectum.app
        GENERATE_INFOPLIST_FILE: NO
        SWIFT_VERSION: "6.0"
        ENABLE_HARDENED_RUNTIME: YES
    dependencies:
      - package: Supabase
  ConnectumTests:
    type: bundle.unit-test
    platform: macOS
    sources: [ConnectumTests]
    dependencies:
      - target: Connectum
schemes:
  Connectum:
    build:
      targets:
        Connectum: all
    test:
      targets: [ConnectumTests]
```

- [ ] **Step 2: Write a minimal Info.plist**

`apps/Connectum/Connectum/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>ko</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleName</key><string>$(PRODUCT_NAME)</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
  <key>NSHumanReadableCopyright</key><string>Connectum</string>
</dict>
</plist>
```

- [ ] **Step 3: Write the app entry + placeholder root**

`apps/Connectum/Connectum/ConnectumApp.swift`:
```swift
import SwiftUI

@main
struct ConnectumApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
    }
}
```

`apps/Connectum/Connectum/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("Connectum")
            .frame(minWidth: 900, minHeight: 600)
    }
}
```

- [ ] **Step 4: Generate the Xcode project and build**

Run: `cd apps/Connectum && xcodegen generate`
Expected: `Created project at .../Connectum.xcodeproj`.
Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **` (Swift Package resolution for supabase-swift runs on first build).

- [ ] **Step 5: Commit**

```bash
git add apps/Connectum/project.yml apps/Connectum/Connectum/ConnectumApp.swift apps/Connectum/Connectum/Info.plist apps/Connectum/Connectum/App/RootView.swift
git commit -m "feat(app): SwiftUI macOS scaffold via XcodeGen"
```

---

## Task 12: Design tokens (Raycast palette + spacing + typography)

**Files:**
- Create: `apps/Connectum/Connectum/DesignSystem/Palette.swift`
- Create: `apps/Connectum/Connectum/DesignSystem/Spacing.swift`
- Create: `apps/Connectum/Connectum/DesignSystem/Typography.swift`
- Test: `apps/Connectum/ConnectumTests/DesignTokenTests.swift`

- [ ] **Step 1: Write the failing test**

`apps/Connectum/ConnectumTests/DesignTokenTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import Connectum

final class DesignTokenTests: XCTestCase {
    func testCanvasHexMatchesRaycast() {
        XCTAssertEqual(Palette.canvas.hexString, "07080A")
    }
    func testSurfaceLadderIsDistinct() {
        let ladder = [Palette.canvas, Palette.surface, Palette.surfaceElevated, Palette.surfaceCard]
        let hexes = Set(ladder.map { $0.hexString })
        XCTAssertEqual(hexes.count, 4, "surface ladder steps must be distinct")
    }
    func testSpacingBaseIsEightPointScale() {
        XCTAssertEqual(Spacing.sm, 8)
        XCTAssertEqual(Spacing.xl, 24)
    }
    func testRadiusScale() {
        XCTAssertEqual(Radius.button, 8)
        XCTAssertEqual(Radius.card, 10)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `Palette`, `Spacing`, `Radius`, `hexString` undefined.

- [ ] **Step 3: Implement the tokens**

`apps/Connectum/Connectum/DesignSystem/Palette.swift`:
```swift
import SwiftUI

enum Palette {
    // Surface ladder (dark-only). Depth comes from these steps, never shadows.
    static let canvas          = Color(hex: "07080A")
    static let surface         = Color(hex: "0D0D0D")
    static let surfaceElevated = Color(hex: "101111")
    static let surfaceCard     = Color(hex: "121212")
    // Text
    static let ink      = Color(hex: "F4F4F6")
    static let body     = Color(hex: "CDCDCD")
    static let muted    = Color(hex: "9C9C9D")
    static let ash      = Color(hex: "6A6B6C") // disabled
    // Border
    static let hairline = Color(hex: "242728")
    // CTA
    static let ctaFill        = Color.white
    static let ctaFillPressed = Color(hex: "E8E8E8")
    static let ctaText        = Color.black
    // Semantic accents (status only — never chrome/CTA)
    static let accentBlue   = Color(hex: "57C1FF")
    static let accentRed    = Color(hex: "FF6161")
    static let accentGreen  = Color(hex: "59D499")
    static let accentYellow = Color(hex: "FFC533")
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    // Test helper: round-trip the resolved sRGB components to an uppercase hex string.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
```

`apps/Connectum/Connectum/DesignSystem/Spacing.swift`:
```swift
import Foundation

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 8
    static let md:  CGFloat = 12
    static let lg:  CGFloat = 16
    static let xl:  CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let badge:  CGFloat = 4
    static let row:    CGFloat = 6
    static let button: CGFloat = 8
    static let card:   CGFloat = 10
    static let modal:  CGFloat = 16
}
```

`apps/Connectum/Connectum/DesignSystem/Typography.swift`:
```swift
import SwiftUI

// Paperlogy type scale (weights 400/500/600). Falls back to system if the
// bundled font is unavailable so the app still renders during early setup.
enum Typography {
    static func paperlogy(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium:   name = "Paperlogy-Medium"
        case .semibold: name = "Paperlogy-SemiBold"
        default:        name = "Paperlogy-Regular"
        }
        return Font.custom(name, size: size)
    }
    static let cardTitle = paperlogy(24, .medium)
    static let body      = paperlogy(16, .regular)
    static let caption   = paperlogy(12, .regular)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: PASS — `DesignTokenTests` all green.

- [ ] **Step 5: Commit**

```bash
git add apps/Connectum/Connectum/DesignSystem apps/Connectum/ConnectumTests/DesignTokenTests.swift
git commit -m "feat(app): Raycast design tokens (palette/spacing/typography)"
```

---

## Task 13: Bundle the Paperlogy font

**Files:**
- Create: `apps/Connectum/Connectum/Resources/Fonts/` (place `Paperlogy-Regular.ttf`, `Paperlogy-Medium.ttf`, `Paperlogy-SemiBold.ttf`)
- Modify: `apps/Connectum/project.yml` (already maps `ATSApplicationFontsPath: Fonts`; ensure fonts copy into the bundle)

- [ ] **Step 1: Add the font files**

Download Paperlogy (the operator has the licensed `.ttf` weights) and place exactly:
```
apps/Connectum/Connectum/Resources/Fonts/Paperlogy-Regular.ttf
apps/Connectum/Connectum/Resources/Fonts/Paperlogy-Medium.ttf
apps/Connectum/Connectum/Resources/Fonts/Paperlogy-SemiBold.ttf
```

- [ ] **Step 2: Ensure XcodeGen copies the fonts under a `Fonts` folder reference**

Edit `apps/Connectum/project.yml` — replace the `sources: [Connectum]` line of the `Connectum` target with:
```yaml
    sources:
      - Connectum
      - path: Connectum/Resources/Fonts
        name: Fonts
        type: folder
```
A `type: folder` reference copies the directory into the bundle as `Fonts/`, which matches `ATSApplicationFontsPath`.

- [ ] **Step 3: Regenerate and build**

Run: `cd apps/Connectum && xcodegen generate && cd - && xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Verify the font is registered at runtime**

Add a temporary check to `RootView` body (we revert in Task 15 when the real shell lands): set the `Text("Connectum")` font to `Typography.cardTitle`, run the app:
Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO` then launch the built `.app` from `~/Library/Developer/Xcode/DerivedData/.../Connectum.app`.
Expected: title renders in Paperlogy (visibly different from system font). If it falls back to system, the font filename/PostScript name is wrong — verify with `mdls -name com_apple_ats_name_postscript apps/Connectum/Connectum/Resources/Fonts/Paperlogy-Regular.ttf` and align `Typography.swift` names.

- [ ] **Step 5: Commit**

```bash
git add apps/Connectum/project.yml apps/Connectum/Connectum/Resources/Fonts
git commit -m "feat(app): bundle Paperlogy font"
```

---

## Task 14: Localization (ko default + en)

**Files:**
- Create: `apps/Connectum/Connectum/Localization/Localizable.xcstrings`
- Test: `apps/Connectum/ConnectumTests/LocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

`apps/Connectum/ConnectumTests/LocalizationTests.swift`:
```swift
import XCTest
@testable import Connectum

final class LocalizationTests: XCTestCase {
    func testKoreanLoginTitle() {
        let s = String(localized: "auth.login.title",
                       bundle: .main, locale: Locale(identifier: "ko"))
        XCTAssertEqual(s, "로그인")
    }
    func testEnglishLoginTitle() {
        let s = String(localized: "auth.login.title",
                       bundle: .main, locale: Locale(identifier: "en"))
        XCTAssertEqual(s, "Sign in")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — keys resolve to `auth.login.title` (no catalog) ≠ expected.

- [ ] **Step 3: Create the String Catalog**

`apps/Connectum/Connectum/Localization/Localizable.xcstrings`:
```json
{
  "sourceLanguage" : "ko",
  "strings" : {
    "auth.login.title" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "로그인" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sign in" } }
      }
    },
    "auth.login.email" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "이메일" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Email" } }
      }
    },
    "auth.login.password" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "비밀번호" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Password" } }
      }
    },
    "auth.login.submit" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "로그인" } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sign in" } }
      }
    }
  },
  "version" : "1.0"
}
```

- [ ] **Step 4: Register `en` as a known localization**

Edit `apps/Connectum/project.yml`, add under `targets.Connectum.info.properties`:
```yaml
        CFBundleLocalizations:
          - ko
          - en
```
Then regenerate: `cd apps/Connectum && xcodegen generate && cd -`

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: PASS — both localization tests green.

- [ ] **Step 6: Commit**

```bash
git add apps/Connectum/Connectum/Localization apps/Connectum/project.yml
git commit -m "feat(app): ko/en localization catalog"
```

---

## Task 15: Supabase Auth + Login screen + authenticated shell

**Files:**
- Create: `apps/Connectum/Connectum/Supabase/SupabaseClientProvider.swift`
- Create: `apps/Connectum/Connectum/Supabase/AuthService.swift`
- Create: `apps/Connectum/Connectum/Features/Auth/AuthViewModel.swift`
- Create: `apps/Connectum/Connectum/Features/Auth/LoginView.swift`
- Modify: `apps/Connectum/Connectum/App/RootView.swift`
- Test: `apps/Connectum/ConnectumTests/AuthViewModelTests.swift`

- [ ] **Step 1: Write the failing test (view-model logic with a fake auth service)**

`apps/Connectum/ConnectumTests/AuthViewModelTests.swift`:
```swift
import XCTest
@testable import Connectum

final class AuthViewModelTests: XCTestCase {
    @MainActor
    func testSuccessfulSignInSetsAuthenticated() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        vm.email = "a@b.com"; vm.password = "secret"
        await vm.signIn()
        XCTAssertTrue(vm.isAuthenticated)
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testFailedSignInShowsError() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .failure(AuthError.invalid)))
        vm.email = "a@b.com"; vm.password = "wrong"
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testEmptyFieldsBlockSignIn() async {
        let vm = AuthViewModel(auth: FakeAuth(result: .success(())))
        await vm.signIn()
        XCTAssertFalse(vm.isAuthenticated)
        XCTAssertNotNil(vm.errorMessage)
    }
}

enum AuthError: Error { case invalid }
struct FakeAuth: AuthProviding {
    let result: Result<Void, Error>
    func signIn(email: String, password: String) async throws {
        if case .failure(let e) = result { throw e }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: FAIL — `AuthViewModel`, `AuthProviding` undefined.

- [ ] **Step 3: Implement the Supabase client provider**

`apps/Connectum/Connectum/Supabase/SupabaseClientProvider.swift`:
```swift
import Foundation
import Supabase

// Reads the Connectum project URL + anon key from Info.plist (injected at build).
// For local dev, set SUPABASE_URL/SUPABASE_ANON_KEY in a build setting or scheme env.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        let url = ProcessInfo.processInfo.environment["SUPABASE_URL"]
            ?? "http://127.0.0.1:54321"
        let anon = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] ?? ""
        return SupabaseClient(supabaseURL: URL(string: url)!, supabaseKey: anon)
    }()
}
```

- [ ] **Step 4: Implement the auth abstraction + concrete service**

`apps/Connectum/Connectum/Supabase/AuthService.swift`:
```swift
import Foundation
import Supabase

// Protocol so the view model is testable without the network.
protocol AuthProviding {
    func signIn(email: String, password: String) async throws
}

struct SupabaseAuthService: AuthProviding {
    let client: SupabaseClient
    init(client: SupabaseClient = SupabaseClientProvider.shared) { self.client = client }
    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }
}
```

- [ ] **Step 5: Implement the view model**

`apps/Connectum/Connectum/Features/Auth/AuthViewModel.swift`:
```swift
import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var isAuthenticated = false
    var isLoading = false
    var errorMessage: String?

    private let auth: AuthProviding
    init(auth: AuthProviding = SupabaseAuthService()) { self.auth = auth }

    func signIn() async {
        errorMessage = nil
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = String(localized: "auth.error.empty")
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await auth.signIn(email: email, password: password)
            isAuthenticated = true
        } catch {
            errorMessage = String(localized: "auth.error.failed")
        }
    }
}
```

- [ ] **Step 6: Add the two new error strings to the catalog**

Add to `apps/Connectum/Connectum/Localization/Localizable.xcstrings` `strings` object:
```json
    "auth.error.empty" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "이메일과 비밀번호를 입력하세요." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Enter email and password." } }
      }
    },
    "auth.error.failed" : {
      "localizations" : {
        "ko" : { "stringUnit" : { "state" : "translated", "value" : "로그인에 실패했습니다." } },
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Sign in failed." } }
      }
    },
```

- [ ] **Step 7: Run test to verify it passes**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`
Expected: PASS — all `AuthViewModelTests` green.

- [ ] **Step 8: Implement the login view + root routing (Raycast-styled)**

`apps/Connectum/Connectum/Features/Auth/LoginView.swift`:
```swift
import SwiftUI

struct LoginView: View {
    @Bindable var vm: AuthViewModel

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Text("Connectum").font(Typography.cardTitle).foregroundStyle(Palette.ink)
            Text("auth.login.title").font(Typography.caption).foregroundStyle(Palette.muted)

            VStack(spacing: Spacing.sm) {
                TextField("auth.login.email", text: $vm.email)
                    .textFieldStyle(.plain).padding(Spacing.md)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
                SecureField("auth.login.password", text: $vm.password)
                    .textFieldStyle(.plain).padding(Spacing.md)
                    .background(Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button).stroke(Palette.hairline))
            }
            .frame(width: 320)

            if let err = vm.errorMessage {
                Text(err).font(Typography.caption).foregroundStyle(Palette.accentRed)
            }

            Button { Task { await vm.signIn() } } label: {
                Text("auth.login.submit").font(Typography.body)
                    .foregroundStyle(Palette.ctaText)
                    .frame(width: 320, height: 36)
                    .background(Palette.ctaFill)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vm.isLoading)
        }
        .padding(Spacing.xxl)
        .frame(minWidth: 900, minHeight: 600)
        .background(Palette.canvas)
        .foregroundStyle(Palette.body)
    }
}
```

`apps/Connectum/Connectum/App/RootView.swift` (replace entire file):
```swift
import SwiftUI

struct RootView: View {
    @State private var vm = AuthViewModel()

    var body: some View {
        Group {
            if vm.isAuthenticated {
                AuthenticatedShell()
            } else {
                LoginView(vm: vm)
            }
        }
    }
}

// Phase 0 placeholder shell — Phase 1b replaces with the operational DB.
struct AuthenticatedShell: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Connectum").font(Typography.cardTitle).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(Spacing.lg)
            .frame(width: 240)
            .background(Palette.surface)
            Divider().overlay(Palette.hairline)
            VStack { Text("운영 DB (Phase 1)").font(Typography.body).foregroundStyle(Palette.muted) }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
```

- [ ] **Step 9: Build and run against local Supabase**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO`
Expected: `** BUILD SUCCEEDED **`.
Create a test user: `supabase db query "select 1;"` then via the local Studio (`http://127.0.0.1:54323` → Authentication → Add user) add `a@b.com` / `secret`. Launch the built app with env `SUPABASE_URL=http://127.0.0.1:54321` and the local `SUPABASE_ANON_KEY` (from `supabase status`), sign in.
Expected: login succeeds and the authenticated shell ("운영 DB (Phase 1)") renders in Raycast dark styling + Paperlogy.

- [ ] **Step 10: Commit**

```bash
git add apps/Connectum/Connectum/Supabase apps/Connectum/Connectum/Features apps/Connectum/Connectum/App/RootView.swift apps/Connectum/Connectum/Localization/Localizable.xcstrings apps/Connectum/ConnectumTests/AuthViewModelTests.swift
git commit -m "feat(app): supabase auth login + authenticated shell"
```

---

## Phase 0 Done — Definition of Done

- [ ] `supabase start` + `supabase db reset` apply all migrations cleanly; `cron.job` has `connectum-sync`.
- [ ] All three spikes (`spike_supabase_mgmt`, `spike_amplitude_export`, `spike_axiom_datasets`) ran against real free-plan credentials; results (incl. any 401/403) recorded in commits. **Amplitude access result determines whether Phase 1 uses Export API or the User Activity fallback.**
- [ ] `deno test supabase/functions/` — all unit tests pass (chunk planner, amplitude mapper, oauth exchange, health).
- [ ] `xcodebuild ... test` — all XCTests pass (design tokens, localization, auth view model).
- [ ] The app builds, signs in via Supabase Auth, and renders the authenticated shell in Raycast dark + Paperlogy + ko/en.

---

## Self-Review Notes (author)

- **Spec coverage:** This plan covers spec §3 (core schema), §4 (architecture skeleton: app↔Supabase↔Edge Functions), §6.1 (OAuth token-exchange), §7 (sync engine skeleton + pg_cron), §9 (design tokens), §10 (i18n), §11 (Vault/RLS/Keychain-ready auth), and the §12 Phase 0 + §13 spikes. **Deferred to later plans (by design):** §6.2–6.4 full ingestion + Vertex (Plan 2/3), §8 operational DB & user detail (Plan 3), §8.3–8.4 views/dashboard (Phase 2). No spec requirement assigned to Phase 0 is missing.
- **Placeholders:** None — every code/test/command step is concrete. The only intentional runtime placeholders are the local `service_role key` (a real secret the operator pastes) and the operator-provided Paperlogy `.ttf` files, both explicitly called out.
- **Type consistency:** `AuthProviding.signIn(email:password:)` is used identically in `FakeAuth`, `SupabaseAuthService`, and `AuthViewModel`. `Palette`/`Spacing`/`Radius`/`Typography` names match between tokens and consumers. `planWindows`, `mapExportRow`, `buildTokenRequest`/`parseTokenResponse` signatures match their tests.
