# Connectum Phase 1a-iii — Amplitude Event Ingestion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sync Amplitude events for a service into `crm_user_event` (matched users only) and refresh each matched user's `amplitude_profile` (OS/device/geo) — by exporting a time window, parsing the ZIP→gzip→NDJSON, filtering to users present in `crm_user`, de-duplicating on the event `uuid`, and advancing a time cursor.

**Architecture:** A new `amplitude-sync` Edge Function takes a `service_id`, reads the service's Amplitude credentials from Vault, fetches the Export API for a cursor-bounded window, parses the archive with `zip.js` + `DecompressionStream`, maps rows to events (keeping only users in `crm_user` for that service), upserts into `crm_user_event` (conflict on a new unique `event_uuid`), updates `crm_user.amplitude_profile` from each user's latest event, and stores the window end as the cursor. Pure modules (gunzip/NDJSON, row map, profile extract) are unit-tested; the ZIP-archive path and live flow are verified against real Amplitude data.

**Tech Stack:** Deno 2.7 Edge Functions, `jsr:@zip-js/zip-js`, `DecompressionStream("gzip")`, Amplitude Export API. Builds on Phase 0 schema + Plan 2 (`_shared/amplitude.ts`, vault) + Plan 3 (`crm_user` populated). **De-risked:** a spike confirmed the Export ZIP layout (`<proj>/<proj>_<date>_<hour>#<part>.json.gz`, gzipped NDJSON) and that zip.js + DecompressionStream parse it in Deno; event fields include `uuid` (dedup), `user_id`, `event_type`, `event_time` (`"YYYY-MM-DD HH:MM:SS.ffffff"`), `os_name`, `device_family`, `device_type`, `platform`, `country`, `region`, `city`.

**Prerequisites:** Phase 0 + Plans 2-3 merged to `main`. Local stack running with `crm_user` populated (357 Archy users from Plan 3; re-run the Plan 3 seed+sync after any DB reset). New branch: `git checkout -b phase1a-amplitude-ingestion`.

---

## File Structure

```
supabase/
├─ migrations/
│  └─ 0006_event_uuid.sql                 # crm_user_event.event_uuid + unique index
└─ functions/
   ├─ _shared/
   │  ├─ amplitude.ts                      # ADD exportUrl(region,start,end)
   │  └─ amplitude_export.ts               # gunzipNdjson, parseExportZip
   │  └─ amplitude_export.test.ts          # gunzipNdjson (synthetic gzip)
   ├─ sync/
   │  ├─ amplitude_map.ts                  # EXTEND: event_uuid; ADD extractProfiles
   │  └─ amplitude_map.test.ts             # update + profile tests
   └─ amplitude-sync/
      └─ index.ts                          # export → parse → match → upsert + profile + cursor
```

---

## Task 1: Migration — `event_uuid` dedup key

**Files:**
- Create: `supabase/migrations/0006_event_uuid.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Dedup key for Amplitude events (the export's per-event `uuid`).
alter table public.crm_user_event add column if not exists event_uuid text;
create unique index if not exists crm_user_event_uuid_key on public.crm_user_event (event_uuid);
```

- [ ] **Step 2: Apply WITHOUT wiping data (preserves the 357 crm_users)**

Run: `supabase migration up`
Expected: applies `0006` only; ends without error. (Do NOT use `supabase db reset` — it would wipe `crm_user`.)
Verify: `supabase db query "select column_name from information_schema.columns where table_name='crm_user_event' and column_name='event_uuid';"` → returns `event_uuid`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0006_event_uuid.sql
git commit -m "feat(db): add crm_user_event.event_uuid dedup key"
```

---

## Task 2: Export URL builder + extend `amplitude.ts`

**Files:**
- Modify: `supabase/functions/_shared/amplitude.ts`
- Modify: `supabase/functions/_shared/amplitude.test.ts`

- [ ] **Step 1: Add the failing test**

Append to `supabase/functions/_shared/amplitude.test.ts`:
```typescript
import { exportUrl } from "./amplitude.ts";

Deno.test("exportUrl builds a window with YYYYMMDDTHH stamps", () => {
  const url = exportUrl("us", new Date("2026-06-07T12:00:00Z"), new Date("2026-06-07T15:00:00Z"));
  assertEquals(url, "https://amplitude.com/api/2/export?start=20260607T12&end=20260607T15");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `deno test supabase/functions/_shared/amplitude.test.ts`
Expected: FAIL — `exportUrl` is not exported.

- [ ] **Step 3: Implement (reuse the existing stampHour by exporting it)**

In `supabase/functions/_shared/amplitude.ts`, change `function stampHour` to `export function stampHour` and append:
```typescript
// General export window URL (start inclusive hour, end inclusive hour), YYYYMMDDTHH.
export function exportUrl(region: string | undefined, start: Date, end: Date): string {
  return `https://${amplitudeHost(region)}/api/2/export?start=${stampHour(start)}&end=${stampHour(end)}`;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `deno test supabase/functions/_shared/amplitude.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/amplitude.ts supabase/functions/_shared/amplitude.test.ts
git commit -m "feat(functions): exportUrl window builder"
```

---

## Task 3: ZIP/gzip/NDJSON parser

**Files:**
- Create: `supabase/functions/_shared/amplitude_export.ts`
- Test: `supabase/functions/_shared/amplitude_export.test.ts`

- [ ] **Step 1: Write the failing test (synthetic gzip via CompressionStream)**

`supabase/functions/_shared/amplitude_export.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { gunzipNdjson } from "./amplitude_export.ts";

async function gzip(s: string): Promise<Uint8Array> {
  const stream = new Blob([s]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

Deno.test("gunzipNdjson decompresses and parses newline-delimited JSON", async () => {
  const gz = await gzip('{"a":1}\n{"a":2,"b":"x"}\n');
  const rows = await gunzipNdjson(gz);
  assertEquals(rows.length, 2);
  assertEquals(rows[0].a, 1);
  assertEquals(rows[1].b, "x");
});

Deno.test("gunzipNdjson ignores blank lines", async () => {
  const gz = await gzip('{"a":1}\n\n');
  assertEquals((await gunzipNdjson(gz)).length, 1);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `deno test supabase/functions/_shared/amplitude_export.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

`supabase/functions/_shared/amplitude_export.ts`:
```typescript
import { ZipReader, BlobReader, Uint8ArrayWriter, configure } from "jsr:@zip-js/zip-js@2";

configure({ useWebWorkers: false });

type Row = Record<string, unknown>;

// Gunzip a gzip buffer and parse its newline-delimited JSON.
export async function gunzipNdjson(gz: Uint8Array): Promise<Row[]> {
  const text = await new Response(
    new Blob([gz]).stream().pipeThrough(new DecompressionStream("gzip")),
  ).text();
  return text.split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l) as Row);
}

// Parse a full Amplitude Export ZIP: each entry is a gzipped NDJSON file.
export async function parseExportZip(bytes: Uint8Array): Promise<Row[]> {
  const reader = new ZipReader(new BlobReader(new Blob([bytes])));
  const out: Row[] = [];
  for (const entry of await reader.getEntries()) {
    if (!entry.filename.endsWith(".gz") || !entry.getData) continue;
    const gz = await entry.getData(new Uint8ArrayWriter());
    out.push(...await gunzipNdjson(gz));
  }
  await reader.close();
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `deno test supabase/functions/_shared/amplitude_export.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/amplitude_export.ts supabase/functions/_shared/amplitude_export.test.ts
git commit -m "feat(functions): Amplitude export ZIP/gzip/NDJSON parser"
```

---

## Task 4: Extend mapper + profile extractor

**Files:**
- Modify: `supabase/functions/sync/amplitude_map.ts`
- Modify: `supabase/functions/sync/amplitude_map.test.ts`

- [ ] **Step 1: Update the tests (add event_uuid + extractProfiles)**

Replace the contents of `supabase/functions/sync/amplitude_map.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { mapExportRow, extractProfiles } from "./amplitude_map.ts";

Deno.test("mapExportRow keeps matched users, carries event_uuid, normalizes fields", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const row = {
    uuid: "ev-1", user_id: "u1", event_type: "login", event_time: "2026-06-01 03:04:05.000000",
    os_name: "Chrome", device_family: "Mac", platform: "Web", event_properties: { plan: "free" },
  };
  const m = mapExportRow(row, matched);
  assertEquals(m?.event_uuid, "ev-1");
  assertEquals(m?.crm_user_id, "crm-1");
  assertEquals(m?.event_type, "login");
  assertEquals(m?.event_time, "2026-06-01T03:04:05.000000Z");
  assertEquals(m?.os, "Chrome");
  assertEquals(m?.props.plan, "free");
});

Deno.test("mapExportRow drops unmatched / anonymous users", () => {
  assertEquals(mapExportRow({ uuid: "x", user_id: "ghost", event_type: "e", event_time: "2026-06-01 00:00:00" }, new Map()), null);
  assertEquals(mapExportRow({ uuid: "y", event_type: "e", event_time: "2026-06-01 00:00:00" }, new Map([["u1", "c1"]])), null);
});

Deno.test("extractProfiles keeps the latest event's device/geo per matched user", () => {
  const matched = new Map([["u1", "crm-1"]]);
  const rows = [
    { user_id: "u1", event_time: "2026-06-01 01:00:00", os_name: "Chrome", device_family: "Mac", device_type: "Mac", country: "KR", region: "Seoul", city: "Seoul", platform: "Web" },
    { user_id: "u1", event_time: "2026-06-02 09:00:00", os_name: "Safari", device_family: "iPhone", device_type: "iPhone", country: "KR", region: "Busan", city: "Busan", platform: "Web" },
    { user_id: "ghost", event_time: "2026-06-03 00:00:00", os_name: "X" },
  ];
  const profiles = extractProfiles(rows, matched);
  assertEquals(profiles.size, 1);
  const p = profiles.get("crm-1")!;
  assertEquals(p.os, "Safari");           // latest
  assertEquals(p.region, "Busan");
  assertEquals(p.last_event_time, "2026-06-02T09:00:00Z");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `deno test supabase/functions/sync/amplitude_map.test.ts`
Expected: FAIL — `extractProfiles` not exported / `event_uuid` missing.

- [ ] **Step 3: Update the implementation**

Replace `supabase/functions/sync/amplitude_map.ts`:
```typescript
export interface ExportRow {
  uuid?: string; user_id?: string; event_type: string; event_time: string;
  os_name?: string; device_family?: string; device_type?: string; platform?: string;
  country?: string; region?: string; city?: string;
  event_properties?: Record<string, unknown>;
}
export interface MappedEvent {
  event_uuid: string | null; crm_user_id: string; event_type: string; event_time: string;
  platform: string | null; os: string | null; browser: string | null;
  props: Record<string, unknown>;
}

// Amplitude export event_time is "YYYY-MM-DD HH:MM:SS.ffffff"; normalize to ISO (UTC-assumed).
function toIso(t: string): string {
  return t.replace(" ", "T") + "Z";
}

// matchedUsers: source_user_id -> crm_user.id. Only registered/matched users are kept.
export function mapExportRow(row: ExportRow, matchedUsers: Map<string, string>): MappedEvent | null {
  if (!row.user_id) return null;
  const crmId = matchedUsers.get(row.user_id);
  if (!crmId) return null;
  return {
    event_uuid: row.uuid ?? null,
    crm_user_id: crmId,
    event_type: row.event_type,
    event_time: toIso(row.event_time),
    platform: row.platform ?? null,
    os: row.os_name ?? null,
    browser: row.device_family ?? null,
    props: row.event_properties ?? {},
  };
}

export interface Profile {
  os: string | null; platform: string | null; device_family: string | null; device_type: string | null;
  country: string | null; region: string | null; city: string | null; last_event_time: string | null;
}

// Latest (max event_time) device/geo snapshot per matched user.
export function extractProfiles(rows: ExportRow[], matchedUsers: Map<string, string>): Map<string, Profile> {
  const latestTime = new Map<string, string>();
  const out = new Map<string, Profile>();
  for (const row of rows) {
    if (!row.user_id) continue;
    const crmId = matchedUsers.get(row.user_id);
    if (!crmId) continue;
    const iso = toIso(row.event_time);
    const prev = latestTime.get(crmId);
    if (prev != null && iso <= prev) continue;
    latestTime.set(crmId, iso);
    out.set(crmId, {
      os: row.os_name ?? null, platform: row.platform ?? null,
      device_family: row.device_family ?? null, device_type: row.device_type ?? null,
      country: row.country ?? null, region: row.region ?? null, city: row.city ?? null,
      last_event_time: iso,
    });
  }
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `deno test supabase/functions/sync/amplitude_map.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/sync/amplitude_map.ts supabase/functions/sync/amplitude_map.test.ts
git commit -m "feat(functions): event_uuid + amplitude profile extractor"
```

---

## Task 5: `amplitude-sync` handler

**Files:**
- Create: `supabase/functions/amplitude-sync/index.ts`

- [ ] **Step 1: Implement the handler**

`supabase/functions/amplitude-sync/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { exportUrl, basicAuth } from "../_shared/amplitude.ts";
import { parseExportZip } from "../_shared/amplitude_export.ts";
import { mapExportRow, extractProfiles, type ExportRow } from "../sync/amplitude_map.ts";

// Window: from cursor (or 24h before end) to (now - 2h, data-availability lag), hour-aligned.
function windowEnd(): Date {
  const d = new Date(Date.now() - 2 * 3600 * 1000);
  d.setUTCMinutes(0, 0, 0);
  return d;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { service_id } = await req.json().catch(() => ({ service_id: undefined }));
  const { data: run } = await db.from("sync_run")
    .insert({ service_id, source: "amplitude", status: "running" }).select("id").single();
  try {
    const { data: svc, error: svcErr } = await db.from("service")
      .select("id, amplitude_account_id").eq("id", service_id).single();
    if (svcErr) throw svcErr;
    if (!svc.amplitude_account_id) throw new Error("service has no amplitude_account");
    const { data: acct } = await db.from("amplitude_account")
      .select("region, api_key_ref, secret_key_ref").eq("id", svc.amplitude_account_id).single();
    const apiKey = await getSecret(acct!.api_key_ref);
    const secret = await getSecret(acct!.secret_key_ref);

    const end = windowEnd();
    const { data: cur } = await db.from("sync_cursor")
      .select("cursor_value").eq("service_id", service_id).eq("source", "amplitude").eq("scope_key", "events").maybeSingle();
    const start = cur?.cursor_value ? new Date(cur.cursor_value) : new Date(end.getTime() - 24 * 3600 * 1000);
    if (start >= end) {
      await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats: { skipped: "no new window" } }).eq("id", run!.id);
      return new Response(JSON.stringify({ run_id: run!.id, events: 0, skipped: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const res = await fetch(exportUrl(acct!.region, start, end), { headers: { Authorization: basicAuth(apiKey, secret) } });
    let events = 0, profilesUpdated = 0;
    if (res.status === 200) {
      const bytes = new Uint8Array(await res.arrayBuffer());
      const rows = await parseExportZip(bytes) as ExportRow[];

      // Matched users for this service.
      const matched = new Map<string, string>();
      const { data: users } = await db.from("crm_user").select("id, source_user_id").eq("service_id", service_id);
      for (const u of users ?? []) matched.set(u.source_user_id, u.id);

      const mapped = rows.map((r) => mapExportRow(r, matched)).filter((m): m is NonNullable<typeof m> => m !== null && m.event_uuid !== null);
      if (mapped.length) {
        const { error } = await db.from("crm_user_event").upsert(
          mapped.map((m) => ({ event_uuid: m.event_uuid, crm_user_id: m.crm_user_id, event_type: m.event_type, event_time: m.event_time, platform: m.platform, os: m.os, browser: m.browser, props: m.props })),
          { onConflict: "event_uuid" });
        if (error) throw error;
        events = mapped.length;
      }

      const profiles = extractProfiles(rows, matched);
      for (const [crmId, p] of profiles) {
        await db.from("crm_user").update({ amplitude_profile: p, updated_at: new Date().toISOString() }).eq("id", crmId);
        profilesUpdated++;
      }
    } else if (res.status !== 404) {
      await res.body?.cancel();
      throw new Error(`amplitude export -> ${res.status}`);
    } else {
      await res.body?.cancel();
    }

    await db.from("sync_cursor").upsert(
      { service_id, source: "amplitude", scope_key: "events", cursor_value: end.toISOString(), updated_at: new Date().toISOString() },
      { onConflict: "service_id,source,scope_key" });
    await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats: { events, profilesUpdated, window_end: end.toISOString() } }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, events, profilesUpdated }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e) }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/amplitude-sync/index.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/amplitude-sync/index.ts
git commit -m "feat(functions): amplitude-sync (export -> events + profile, dedup, cursor)"
```

---

## Done — Definition of Done

- [ ] `deno test supabase/functions/` — all pass (Plan 3's 25 + exportUrl 1 + export 2 + map now 3 (was 2) = 31).
- [ ] `deno check` on `amplitude-sync/index.ts` clean.
- [ ] Live (controller): with the Archy service having an `amplitude_account` attached and `crm_user` populated, `amplitude-sync` returns `{events: N≥0, profilesUpdated: M}`, `crm_user_event` gains rows for matched users, at least one `crm_user.amplitude_profile` is populated, and a second run does not duplicate events (dedup on `event_uuid`).
- [ ] Results recorded.

---

## Self-Review Notes (author)

- **Spec coverage:** Implements spec §4 step 4 (Amplitude → `crm_user_event` matched-users-only + profile attributes) and §7 (cursor/sync_run). Vertex AI summary + operational UI are later plans.
- **Placeholders:** None. Live-verify ids are inspected/pasted by the controller.
- **Type consistency:** `mapExportRow`/`extractProfiles`/`ExportRow`/`Profile` signatures match tests and handler. `exportUrl`/`basicAuth`/`parseExportZip`/`gunzipNdjson` match. Upsert `onConflict: "event_uuid"` matches the unique index from Task 1; `sync_cursor` onConflict matches its constraint. `crm_user_event` columns (`event_uuid, crm_user_id, event_type, event_time, platform, os, browser, props`) match Phase 0 `0001` + Task 1.
- **Known fuzz:** `event_time` is treated as UTC (`+Z`); Amplitude exports in project-local time, so absolute timestamps may be offset by the project's tz. Acceptable for MVP ordering/"last seen"; a tz-aware fix is a later refinement. `extractProfiles`/`maxCursor`-style comparisons are lexicographic on ISO strings (correct for these formats).
```
