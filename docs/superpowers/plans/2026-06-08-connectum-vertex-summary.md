# Connectum — Vertex AI 3-Line Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** Generate a Korean 3-line AI summary per user from merged data (Supabase profile + Amplitude behavior + contact records) using Vertex AI Gemini (`gemini-3.1-flash-lite`, global endpoint), stored in `crm_user.ai_summary` with an input-hash to skip unchanged regenerations. Callable on demand (app button) and by the orchestrator.

**Architecture:** `_shared/gcp_token.ts` mints a GCP access token from the service-account key (JWT RS256 via Web Crypto → token exchange). `_shared/vertex.ts` builds the prompt (pure) and calls `generateContent`. `summarize-user/index.ts` loads the user + recent events + channel-record blocks, builds the prompt, hashes it, and (if changed or forced) calls Gemini and stores the summary. **De-risked:** a Deno spike already minted a token from the SA key and got a Gemini response.

**Tech Stack:** Deno Edge Functions, Web Crypto (RS256), Vertex AI `gemini-3.1-flash-lite` (global). Secrets in env: `GCP_SA_KEY_B64`, `GCP_PROJECT`, `GCP_LOCATION`, `GCP_MODEL` (in `.env.local`; deploy via `supabase secrets set`).

**Prerequisites:** Plans 0-6 merged. Local stack running. `.env.local` has the GCP vars. Branch `phase1-vertex-summary`.

---

## File Structure
```
supabase/functions/
├─ _shared/gcp_token.ts        # decodeSaKey, getAccessToken
├─ _shared/gcp_token.test.ts   # decodeSaKey (fake key)
├─ _shared/vertex.ts           # buildSummaryPrompt (pure), generateSummary
├─ _shared/vertex.test.ts      # buildSummaryPrompt
└─ summarize-user/index.ts     # handler
```

---

## Task 1: GCP token minter

**Files:** Create `supabase/functions/_shared/gcp_token.ts` + `_shared/gcp_token.test.ts`

- [ ] **Step 1: failing test**
`_shared/gcp_token.test.ts`:
```typescript
import { assertEquals } from "jsr:@std/assert";
import { decodeSaKey } from "./gcp_token.ts";

Deno.test("decodeSaKey parses a base64 service-account json", () => {
  const fake = { client_email: "x@y.iam.gserviceaccount.com", private_key: "PEM" };
  const b64 = btoa(JSON.stringify(fake));
  const sa = decodeSaKey(b64);
  assertEquals(sa.client_email, "x@y.iam.gserviceaccount.com");
  assertEquals(sa.private_key, "PEM");
});
```

- [ ] **Step 2: run (FAIL)** — `deno test supabase/functions/_shared/gcp_token.test.ts`

- [ ] **Step 3: implement**
`supabase/functions/_shared/gcp_token.ts`:
```typescript
function b64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function b64urlStr(s: string): string { return b64url(new TextEncoder().encode(s)); }
function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export interface SaKey { client_email: string; private_key: string; }

export function decodeSaKey(b64: string): SaKey {
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
}

// Mint a short-lived GCP access token from a service-account key (JWT bearer flow).
export async function getAccessToken(saB64: string): Promise<string> {
  const sa = decodeSaKey(saB64);
  const now = Math.floor(Date.now() / 1000);
  const header = b64urlStr(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64urlStr(JSON.stringify({
    iss: sa.client_email, scope: "https://www.googleapis.com/auth/cloud-platform",
    aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  }));
  const signingInput = `${header}.${claims}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)));
  const jwt = `${signingInput}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const tok = await res.json();
  if (!tok.access_token) throw new Error("token exchange failed: " + JSON.stringify(tok));
  return tok.access_token as string;
}
```

- [ ] **Step 4: run (PASS 1)** — same command. **Step 5: commit**
```bash
git add supabase/functions/_shared/gcp_token.ts supabase/functions/_shared/gcp_token.test.ts
git commit -m "feat(functions): GCP access-token minter (JWT RS256)"
```

---

## Task 2: Vertex prompt + call

**Files:** Create `supabase/functions/_shared/vertex.ts` + `_shared/vertex.test.ts`

- [ ] **Step 1: failing test**
`_shared/vertex.test.ts`:
```typescript
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
```

- [ ] **Step 2: run (FAIL)** — `deno test supabase/functions/_shared/vertex.test.ts`

- [ ] **Step 3: implement**
`supabase/functions/_shared/vertex.ts`:
```typescript
type Row = Record<string, unknown>;
export interface PromptUser {
  email?: string | null; source_user_id: string; contact_status?: string;
  supabase_profile?: Row | null; amplitude_profile?: Row | null;
}
export interface PromptEvent { event_type: string; event_time: string; }
export interface PromptRecord { channel?: string; body?: string; occurred_at?: string; }

export function buildSummaryPrompt(user: PromptUser, events: PromptEvent[], records: PromptRecord[]): string {
  const sp = JSON.stringify(user.supabase_profile ?? {});
  const ap = JSON.stringify(user.amplitude_profile ?? {});
  const ev = events.slice(0, 30).map((e) => `${e.event_time} ${e.event_type}`).join("\n");
  const rec = records.map((r) => `[${r.channel ?? "memo"}] ${r.occurred_at ?? ""} ${r.body ?? ""}`).join("\n");
  return [
    "당신은 CRM 분석가입니다. 아래 유저를 한국어 3줄로 요약하세요. 각 줄은 간결하게, 가입 정보·제품 사용 행동·운영 맥락을 종합해 핵심만 담으세요.",
    "",
    `[유저] ${user.email ?? user.source_user_id} (컨택: ${user.contact_status ?? "?"})`,
    `[가입 프로필] ${sp}`,
    `[행동 프로필] ${ap}`,
    "[최근 이벤트]", ev || "없음",
    "[운영 기록]", rec || "없음",
    "", "3줄 요약:",
  ].join("\n");
}

export async function generateSummary(token: string, project: string, location: string, model: string, prompt: string): Promise<string> {
  const url = `https://aiplatform.googleapis.com/v1/projects/${project}/locations/${location}/publishers/google/models/${model}:generateContent`;
  const res = await fetch(url, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ contents: [{ role: "user", parts: [{ text: prompt }] }], generationConfig: { maxOutputTokens: 300, temperature: 0.4 } }),
  });
  const j = await res.json();
  if (!j.candidates) throw new Error("gemini error: " + JSON.stringify(j).slice(0, 300));
  return (j.candidates[0].content.parts as Array<{ text?: string }>).map((p) => p.text ?? "").join("").trim();
}
```

- [ ] **Step 4: run (PASS 1)**. **Step 5: commit**
```bash
git add supabase/functions/_shared/vertex.ts supabase/functions/_shared/vertex.test.ts
git commit -m "feat(functions): Vertex summary prompt builder + generateContent"
```

---

## Task 3: summarize-user handler

**Files:** Create `supabase/functions/summarize-user/index.ts`

- [ ] **Step 1: implement**
`supabase/functions/summarize-user/index.ts`:
```typescript
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getAccessToken } from "../_shared/gcp_token.ts";
import { buildSummaryPrompt, generateSummary } from "../_shared/vertex.ts";

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Body: { crm_user_id, force? }. Builds the prompt, skips if the input hash is
// unchanged (cost control), else calls Gemini and stores the 3-line summary.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { crm_user_id, force } = await req.json();
    const db = adminClient();
    const { data: user, error } = await db.from("crm_user").select("*").eq("id", crm_user_id).single();
    if (error) throw error;
    const { data: events } = await db.from("crm_user_event")
      .select("event_type,event_time").eq("crm_user_id", crm_user_id).order("event_time", { ascending: false }).limit(30);
    const { data: blocks } = await db.from("page_block")
      .select("content").eq("crm_user_id", crm_user_id).eq("type", "channel_record");
    const records = (blocks ?? []).map((b) => b.content as Record<string, unknown>);
    const prompt = buildSummaryPrompt(user, events ?? [], records);
    const hash = await sha256Hex(prompt);
    if (!force && user.ai_summary_input_hash === hash && user.ai_summary) {
      return new Response(JSON.stringify({ skipped: true, ai_summary: user.ai_summary }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const token = await getAccessToken(Deno.env.get("GCP_SA_KEY_B64")!);
    const summary = await generateSummary(
      token, Deno.env.get("GCP_PROJECT")!, Deno.env.get("GCP_LOCATION") ?? "global",
      Deno.env.get("GCP_MODEL") ?? "gemini-3.1-flash-lite", prompt);
    await db.from("crm_user").update({
      ai_summary: summary, ai_summary_generated_at: new Date().toISOString(), ai_summary_input_hash: hash,
    }).eq("id", crm_user_id);
    return new Response(JSON.stringify({ ai_summary: summary }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 2: type-check** — `deno check supabase/functions/summarize-user/index.ts`
- [ ] **Step 3: commit**
```bash
git add supabase/functions/summarize-user/index.ts
git commit -m "feat(functions): summarize-user (Gemini 3-line summary + hash skip)"
```

---

## Done — Definition of Done
- [ ] `deno test supabase/functions/` all pass (29 + gcp_token 1 + vertex 1 = 31).
- [ ] `deno check` summarize-user clean.
- [ ] Live (controller): serve with `--env-file .env.local`, call `summarize-user` for a real Archy user **that has events** (one of the 2 profiled users) → returns a 3-line Korean `ai_summary`; `crm_user.ai_summary` is stored; a second call returns `skipped:true` (hash unchanged).

---

## Self-Review Notes (author)
- **Spec coverage:** §6.4 / §8.5 (Vertex 3-line summary from merged data, hash-skip cost control). Orchestrator auto-regeneration after sync is a follow-up; the app "재생성" button calls this with `force:true`.
- **Placeholders:** None. Secrets read from env (set in `.env.local` / `supabase secrets`).
- **Type consistency:** `getAccessToken`, `buildSummaryPrompt`, `generateSummary` signatures match handler. Writes `ai_summary`/`ai_summary_generated_at`/`ai_summary_input_hash` (Phase 0 `0001` columns). The token mint logic is identical to the verified spike.
```
