# Service Brief Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the embedded AI chat per-service qualitative context ("what is this service") via a Claude-maintained, prompt-edited Service Brief injected into the chat system prompt.

**Architecture:** One `service_brief` row per service holds 6 free-text sections. A new `service-brief` edge function is the single primitive: it gathers available signals (service name, columns, event types — degrading gracefully when only Supabase is connected), then asks Claude to either run an interview step or synthesize/edit the brief. All brief writes go through Claude (no direct field editing). `ai-chat` injects the brief into its system prompt.

**Tech Stack:** Supabase Postgres + Deno edge functions (Claude OAuth via existing `_shared/claude_*`), SwiftUI macOS app (`@Observable`, PDFKit), `deno test` + XCTest.

---

## File Structure

**Backend (Deno):**
- Create `supabase/migrations/20260610100000_service_brief.sql` — table + RLS.
- Create `supabase/functions/_shared/claude_chat.ts` — shared `CLAUDE_CODE_IDENTITY`, `claudeHeaders()`, `claudeComplete()` (extracted from `ai-chat`).
- Create `supabase/functions/service-brief/signals.ts` — `gatherSignals(db, serviceId)`.
- Create `supabase/functions/service-brief/brief.ts` — pure: section constants, prompt builders, JSON parsers, `detectGaps`.
- Create `supabase/functions/service-brief/brief.test.ts` — deno tests for brief.ts.
- Create `supabase/functions/service-brief/index.ts` — HTTP handler, mode dispatch, Claude call, upsert.
- Modify `supabase/functions/ai-chat/index.ts` — import shared `claude_chat.ts`; inject brief block.

**Frontend (SwiftUI):**
- Create `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefModels.swift` — `BriefSections`, `ServiceBrief`, `InterviewStep`.
- Create `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefViewModel.swift`.
- Create `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefView.swift`.
- Create `apps/Connectum/Connectum/Features/ServiceBrief/DocumentTextExtractor.swift` — PDFKit/text extraction.
- Modify `apps/Connectum/Connectum/Data/CrmRepository.swift` — add brief methods to protocol + struct.
- Modify `apps/Connectum/Connectum/Features/AIChat/AIChatView.swift` — empty-brief banner → present `ServiceBriefView`.
- Create `apps/Connectum/ConnectumTests/ServiceBriefTests.swift` — model decode + VM orchestration + extractor.

**Data contract (shared shapes):**
- `BRIEF_SECTIONS = [one_liner, icp, activation, signal_glossary, business_model, current_focus]`.
- Brief status: `empty` | `ready` (injected into chat when `ready`).
- `synthesize` response: `{ sections, status, gaps }`. `interview_step` response: `{ question, options } | { done: true }`.

---

## Phase 1: Brief core + autodraft + prompt-edit + chat injection

### Task 1: Migration — `service_brief` table

**Files:**
- Create: `supabase/migrations/20260610100000_service_brief.sql`

- [ ] **Step 1: Write migration**

```sql
-- Per-service qualitative context brief, authored/maintained by Claude.
-- Injected into ai-chat's system prompt so the assistant understands the service.
create table if not exists public.service_brief (
  service_id uuid primary key references public.service(id) on delete cascade,
  sections jsonb not null default '{}'::jsonb,  -- {one_liner, icp, activation, signal_glossary, business_model, current_focus}
  status text not null default 'empty',          -- 'empty' | 'ready'
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

alter table public.service_brief enable row level security;

drop policy if exists service_brief_select on public.service_brief;
create policy service_brief_select on public.service_brief for select to authenticated using (true);
drop policy if exists service_brief_insert on public.service_brief;
create policy service_brief_insert on public.service_brief for insert to authenticated with check (true);
drop policy if exists service_brief_update on public.service_brief;
create policy service_brief_update on public.service_brief for update to authenticated using (true);
drop policy if exists service_brief_delete on public.service_brief;
create policy service_brief_delete on public.service_brief for delete to authenticated using (true);
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260610100000_service_brief.sql
git commit -m "feat(service-brief): add service_brief table + RLS"
```

### Task 2: `brief.ts` pure helpers (TDD)

**Files:**
- Create: `supabase/functions/service-brief/brief.ts`
- Test: `supabase/functions/service-brief/brief.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectGaps, emptyBrief, parseInterviewJSON, parseSectionsJSON } from "./brief.ts";

Deno.test("emptyBrief has all six keys blank", () => {
  const b = emptyBrief();
  assertEquals(Object.keys(b).sort(), ["activation","business_model","current_focus","icp","one_liner","signal_glossary"]);
  assertEquals(b.one_liner, "");
});

Deno.test("parseSectionsJSON extracts JSON and fills missing keys", () => {
  const out = parseSectionsJSON('noise {"one_liner":"A CRM","icp":"founders"} tail');
  assertEquals(out.one_liner, "A CRM");
  assertEquals(out.icp, "founders");
  assertEquals(out.activation, ""); // missing → blank
});

Deno.test("detectGaps flags blank/too-short sections", () => {
  const b = emptyBrief();
  b.one_liner = "A real one-liner that is long enough to count.";
  const gaps = detectGaps(b);
  assertEquals(gaps.includes("one_liner"), false);
  assertEquals(gaps.includes("icp"), true);
});

Deno.test("parseInterviewJSON reads question/options and done", () => {
  assertEquals(parseInterviewJSON('{"done":true}'), { done: true });
  const q = parseInterviewJSON('{"question":"Who?","options":["A","B"]}');
  assertEquals(q.question, "Who?");
  assertEquals(q.options, ["A","B"]);
});
```

- [ ] **Step 2: Run, verify fail**

Run: `deno test supabase/functions/service-brief/brief.test.ts`
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `brief.ts`**

```ts
export const BRIEF_SECTIONS = [
  "one_liner", "icp", "activation", "signal_glossary", "business_model", "current_focus",
] as const;
export type SectionKey = typeof BRIEF_SECTIONS[number];
export type BriefSections = Record<SectionKey, string>;

export function emptyBrief(): BriefSections {
  return Object.fromEntries(BRIEF_SECTIONS.map((k) => [k, ""])) as BriefSections;
}

function extractJSON(text: string): Record<string, unknown> {
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) throw new Error("Claude가 JSON을 반환하지 않았습니다: " + text.slice(0, 200));
  return JSON.parse(m[0]);
}

export function parseSectionsJSON(text: string): BriefSections {
  const raw = extractJSON(text);
  const out = emptyBrief();
  for (const k of BRIEF_SECTIONS) {
    const v = (raw as Record<string, unknown>)[k];
    if (typeof v === "string") out[k] = v.trim();
  }
  return out;
}

// A section is a "gap" if blank or shorter than 12 chars (placeholder-ish).
export function detectGaps(sections: BriefSections): SectionKey[] {
  return BRIEF_SECTIONS.filter((k) => (sections[k] ?? "").trim().length < 12);
}

export interface InterviewStep { question?: string; options?: string[]; done?: boolean }
export function parseInterviewJSON(text: string): InterviewStep {
  const raw = extractJSON(text) as InterviewStep;
  if (raw.done === true) return { done: true };
  return {
    question: typeof raw.question === "string" ? raw.question : "",
    options: Array.isArray(raw.options) ? raw.options.filter((o) => typeof o === "string") : undefined,
  };
}

const SECTION_LABELS: Record<SectionKey, string> = {
  one_liner: "한 줄 소개 (무엇을 하는 서비스인가)",
  icp: "타깃 고객 / ICP",
  activation: "핵심 활성화·성공 기준 (제대로 쓴다는 것, aha moment)",
  signal_glossary: "핵심 행동·상태 신호의 의미 (이벤트 또는 컬럼/상태가 비즈니스적으로 뜻하는 것)",
  business_model: "비즈니스 모델 (수익화, 무료/유료, 전환 포인트)",
  current_focus: "현재 집중 목표 (지금 가장 신경 쓰는 것)",
};

export interface SignalText { text: string } // rendered signal block

export function buildSynthesizePrompt(args: {
  signals: string;
  document?: string;
  transcript?: { role: string; content: string }[];
  current?: BriefSections;
  userPrompt?: string;
}): string {
  const lines = [
    "당신은 Connectum의 '서비스 브리프' 작성자입니다. 한 서비스의 맥락을 6개 섹션으로 정리합니다.",
    "이 브리프는 다른 LLM(내장 CRM 채팅)이 소비하므로, 각 섹션을 명확·고밀도·모호성 없는 자연어로 쓰세요.",
    "추측 금지: 입력으로 알 수 없는 섹션은 빈 문자열(\"\")로 두세요(거짓을 지어내지 마세요).",
    "",
    "섹션:",
    ...BRIEF_SECTIONS.map((k) => `- ${k}: ${SECTION_LABELS[k]}`),
    "",
    "[연동/데이터 시그널]", args.signals,
  ];
  if (args.current) {
    lines.push("", "[현재 브리프]", JSON.stringify(args.current));
  }
  if (args.userPrompt) {
    lines.push("", "[유저 수정 지시]", args.userPrompt,
      "유저가 명시적으로 바꾸라고 한 섹션만 갱신하고 나머지는 그대로 보존하세요.");
  }
  if (args.document) {
    lines.push("", "[첨부 문서]", args.document.slice(0, 24000));
  }
  if (args.transcript?.length) {
    lines.push("", "[인터뷰 대화]",
      args.transcript.map((m) => `${m.role}: ${m.content}`).join("\n"));
  }
  lines.push("",
    "다음 JSON만 출력하세요(코드펜스·설명·머리말 금지):",
    '{"one_liner":"...","icp":"...","activation":"...","signal_glossary":"...","business_model":"...","current_focus":"..."}');
  return lines.join("\n");
}

export function buildInterviewPrompt(args: {
  signals: string;
  transcript: { role: string; content: string }[];
  targetSections?: SectionKey[];
}): string {
  const targets = (args.targetSections?.length ? args.targetSections : BRIEF_SECTIONS)
    .map((k) => `- ${k}: ${SECTION_LABELS[k]}`);
  return [
    "당신은 서비스 맥락을 캐내는 온보딩 인터뷰어입니다. 원칙:",
    "1) 한 번에 한 질문만. 2) 객관식이 가능한 질문은 옵션을 제시. 3) 시그널로 이미 알 수 있는 건 묻지 않음.",
    "4) 모호한 답은 구체화를 요구('고객이 누구?'에 '헬스케어 기업들'은 답이 아님 — 역할·상황을 캐묻기).",
    "아래 섹션을 채우기 위한 정보를 얻는 게 목표입니다. 충분히 모였으면 종료하세요.",
    "",
    "[채울 섹션]", ...targets,
    "",
    "[연동/데이터 시그널]", args.signals,
    "",
    "[지금까지 대화]",
    args.transcript.length ? args.transcript.map((m) => `${m.role}: ${m.content}`).join("\n") : "(없음)",
    "",
    "다음 JSON만 출력하세요(코드펜스·설명 금지).",
    '아직 물을 게 있으면: {"question":"...","options":["...","..."]}  (options는 객관식일 때만, 생략 가능)',
    '충분하면: {"done":true}',
  ].join("\n");
}
```

- [ ] **Step 4: Run, verify pass**

Run: `deno test supabase/functions/service-brief/brief.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/service-brief/brief.ts supabase/functions/service-brief/brief.test.ts
git commit -m "feat(service-brief): brief section helpers, prompt builders, parsers (TDD)"
```

### Task 3: `signals.ts` — gather available signals

**Files:**
- Create: `supabase/functions/service-brief/signals.ts`

- [ ] **Step 1: Implement** (queries mirror `ai-chat/tools.ts` get_service_overview and createService schema)

```ts
// deno-lint-ignore-file no-explicit-any
export interface Signals {
  service_name: string;
  supabase_project_name: string | null;
  user_columns: string[];
  event_types: string[];
  connections: { supabase: boolean; amplitude: boolean; axiom: boolean };
}

export async function gatherSignals(db: any, serviceId: string): Promise<Signals> {
  const { data: svc } = await db.from("service")
    .select("name,supabase_project_name,supabase_account_id,amplitude_account_id,axiom_account_id")
    .eq("id", serviceId).maybeSingle();
  const { data: st } = await db.from("service_table")
    .select("column_map,display_columns,role").eq("service_id", serviceId).eq("role", "user_table").limit(1);
  const userTable = (st ?? [])[0] ?? {};
  const cols = new Set<string>();
  for (const k of Object.keys((userTable.column_map ?? {}) as Record<string, unknown>)) cols.add(k);
  for (const c of (userTable.display_columns ?? []) as string[]) cols.add(c);

  // Top event types (only if any events exist). Sample, then count in JS.
  let eventTypes: string[] = [];
  const { data: sampleUsers } = await db.from("crm_user").select("id").eq("service_id", serviceId).limit(50);
  const ids = (sampleUsers ?? []).map((r: any) => r.id);
  if (ids.length) {
    const { data: evs } = await db.from("crm_user_event")
      .select("event_type").in("crm_user_id", ids).limit(500);
    const counts: Record<string, number> = {};
    for (const e of (evs ?? []) as any[]) counts[e.event_type] = (counts[e.event_type] ?? 0) + 1;
    eventTypes = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 20).map(([k]) => k);
  }

  return {
    service_name: svc?.name ?? "",
    supabase_project_name: svc?.supabase_project_name ?? null,
    user_columns: [...cols],
    event_types: eventTypes,
    connections: {
      supabase: !!svc?.supabase_account_id,
      amplitude: !!svc?.amplitude_account_id,
      axiom: !!svc?.axiom_account_id,
    },
  };
}

export function renderSignals(s: Signals): string {
  return [
    `서비스명: ${s.service_name || "(미지정)"}`,
    s.supabase_project_name ? `Supabase 프로젝트: ${s.supabase_project_name}` : null,
    `유저 테이블 컬럼: ${s.user_columns.length ? s.user_columns.join(", ") : "(알 수 없음)"}`,
    s.event_types.length
      ? `관측된 주요 이벤트: ${s.event_types.join(", ")}`
      : "이벤트 로그 없음(분석 연동 미설정 또는 데이터 없음) — signal_glossary는 컬럼/상태 기반으로만 작성",
    `연동: supabase=${s.connections.supabase}, amplitude=${s.connections.amplitude}, axiom=${s.connections.axiom}`,
  ].filter(Boolean).join("\n");
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/service-brief/signals.ts
git commit -m "feat(service-brief): signal gathering with graceful no-events degrade"
```

### Task 4: Shared `claude_chat.ts` (extract from ai-chat)

**Files:**
- Create: `supabase/functions/_shared/claude_chat.ts`
- Modify: `supabase/functions/ai-chat/index.ts:7-48` (use shared identity + headers)

- [ ] **Step 1: Create `claude_chat.ts`** (move `CLAUDE_CODE_IDENTITY` + `claudeHeaders` from ai-chat; add non-streaming `claudeComplete`)

```ts
import { claudeEnv } from "./claude_env.ts";
import { tokenForClaudeAccount } from "./claude_token.ts";

// OAuth subscription token only accepted when system block 1 is the Claude Code identity.
export const CLAUDE_CODE_IDENTITY = "You are Claude Code, Anthropic's official CLI for Claude.";

export async function claudeHeaders(): Promise<Record<string, string>> {
  const apiKey = claudeEnv.apiKey();
  if (apiKey) {
    return { "Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" };
  }
  const token = await tokenForClaudeAccount();
  return {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${token}`,
    "anthropic-version": "2023-06-01",
    "anthropic-beta": claudeEnv.oauthBeta(),
  };
}

// Single-shot completion. `instructions` is one or more system text blocks placed
// AFTER the required Claude Code identity block. Returns concatenated text.
// Throws { reauth: true } shape on 401/403 so callers can surface re-connect.
export async function claudeComplete(
  instructions: string[],
  userText: string,
  maxTokens = 2048,
): Promise<string> {
  const system = [
    { type: "text", text: CLAUDE_CODE_IDENTITY },
    ...instructions.map((t) => ({ type: "text", text: t })),
  ];
  const res = await fetch(claudeEnv.apiUrl(), {
    method: "POST",
    headers: await claudeHeaders(),
    body: JSON.stringify({
      model: claudeEnv.model(),
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content: userText }],
    }),
  });
  if (res.status === 401 || res.status === 403) {
    throw new Error("ai_reauth_required:" + (await res.text()));
  }
  if (!res.ok) throw new Error(`claude_error:${res.status}:${await res.text()}`);
  const msg = await res.json();
  return (msg.content as Array<{ type: string; text?: string }>)
    .filter((b) => b.type === "text").map((b) => b.text ?? "").join("").trim();
}
```

- [ ] **Step 2: Refactor `ai-chat/index.ts`** — replace its local `CLAUDE_CODE_IDENTITY` and `claudeHeaders` with an import; keep behavior identical.

In `ai-chat/index.ts`: delete the local `const CLAUDE_CODE_IDENTITY = ...` (line ~9) and the local `async function claudeHeaders()` (lines ~17-34). Add at top:

```ts
import { CLAUDE_CODE_IDENTITY, claudeHeaders } from "../_shared/claude_chat.ts";
```

- [ ] **Step 3: Verify ai-chat still type-checks**

Run: `deno check supabase/functions/ai-chat/index.ts`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/_shared/claude_chat.ts supabase/functions/ai-chat/index.ts
git commit -m "refactor(ai-chat): extract shared claude_chat helper (identity, headers, claudeComplete)"
```

### Task 5: `service-brief/index.ts` handler (synthesize + interview_step)

**Files:**
- Create: `supabase/functions/service-brief/index.ts`

- [ ] **Step 1: Implement handler**

```ts
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { claudeComplete } from "../_shared/claude_chat.ts";
import { gatherSignals, renderSignals } from "./signals.ts";
import {
  buildInterviewPrompt, buildSynthesizePrompt, detectGaps,
  emptyBrief, parseInterviewJSON, parseSectionsJSON, type BriefSections, type SectionKey, BRIEF_SECTIONS,
} from "./brief.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function clean(v: unknown): string { return typeof v === "string" ? v.trim() : ""; }
function errorResponse(e: unknown): Response {
  const msg = String(e);
  if (msg.startsWith("ai_reauth_required")) return json({ code: "ai_reauth_required", message: msg }, 401);
  return json({ error: msg }, 500);
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const serviceId = clean(body.service_id);
  const mode = clean(body.mode);
  if (!serviceId) return json({ error: "service_id required" }, 400);
  const db = adminClient();

  try {
    const signals = renderSignals(await gatherSignals(db, serviceId));

    if (mode === "interview_step") {
      const transcript = Array.isArray(body.transcript) ? body.transcript : [];
      const targets = Array.isArray(body.target_sections)
        ? body.target_sections.filter((s: unknown): s is SectionKey => (BRIEF_SECTIONS as readonly string[]).includes(s as string))
        : undefined;
      const raw = await claudeComplete([buildInterviewPrompt({ signals, transcript, targetSections: targets })],
        "다음 단계를 진행하세요.", 1024);
      return json(parseInterviewJSON(raw));
    }

    // mode === "synthesize" (default)
    const document = clean(body.document) || undefined;
    const userPrompt = clean(body.user_prompt) || undefined;
    const transcript = Array.isArray(body.transcript) ? body.transcript : undefined;
    let current: BriefSections | undefined;
    if (body.current_sections && typeof body.current_sections === "object") {
      current = emptyBrief();
      for (const k of BRIEF_SECTIONS) {
        const v = body.current_sections[k];
        if (typeof v === "string") current[k] = v;
      }
    }

    const prompt = buildSynthesizePrompt({ signals, document, transcript, current, userPrompt });
    const raw = await claudeComplete([prompt], "위 입력으로 6섹션 JSON을 출력하세요.", 3000);
    const sections = parseSectionsJSON(raw);
    const gaps = detectGaps(sections);
    const status = gaps.length === BRIEF_SECTIONS.length ? "empty" : "ready";

    await db.from("service_brief").upsert({
      service_id: serviceId, sections, status, updated_at: new Date().toISOString(),
    }, { onConflict: "service_id" });

    return json({ sections, status, gaps });
  } catch (e) {
    return errorResponse(e);
  }
}

if (import.meta.main) Deno.serve(handle);
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/service-brief/index.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/service-brief/index.ts
git commit -m "feat(service-brief): edge handler for synthesize + interview_step"
```

### Task 6: Inject brief into ai-chat system prompt

**Files:**
- Modify: `supabase/functions/ai-chat/index.ts` (`systemPrompt` + handler start)

- [ ] **Step 1: Add brief fetch + injection.** In `handle()`'s stream start, before `systemPrompt`, fetch the brief; pass it in.

```ts
// after: const overview = await runTool(db, serviceId, "get_service_overview", {});
const { data: briefRow } = await db.from("service_brief")
  .select("sections,status").eq("service_id", serviceId).maybeSingle();
const briefText = briefRow?.status === "ready"
  ? Object.entries(briefRow.sections as Record<string, string>)
      .filter(([, v]) => (v ?? "").trim()).map(([k, v]) => `[${k}] ${v}`).join("\n")
  : "";
const system = systemPrompt(overview, briefText);
```

Change `systemPrompt` signature to add the brief as its own cached block:

```ts
function systemPrompt(serviceContext: string, brief: string): unknown[] {
  const blocks: unknown[] = [
    { type: "text", text: CLAUDE_CODE_IDENTITY },
    {
      type: "text",
      text: "You are Connectum's embedded CRM analyst. Answer questions about the user's customers " +
        "using ONLY the provided tools, which are scoped to the currently selected service. " +
        "Prefer concrete numbers and cite user emails when relevant. Reply in the user's language (Korean or English).\n\n" +
        "Selected service context (overview):\n" + serviceContext,
      cache_control: { type: "ephemeral" },
    },
  ];
  if (brief) {
    blocks.push({
      type: "text",
      text: "Service brief (what this service is — use it to interpret the data and prioritize):\n" + brief,
      cache_control: { type: "ephemeral" },
    });
  }
  return blocks;
}
```

- [ ] **Step 2: Type-check**

Run: `deno check supabase/functions/ai-chat/index.ts`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/ai-chat/index.ts
git commit -m "feat(ai-chat): inject service brief into chat system prompt"
```

### Task 7: Swift models + repository methods

**Files:**
- Create: `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefModels.swift`
- Modify: `apps/Connectum/Connectum/Data/CrmRepository.swift` (protocol + struct)
- Test: `apps/Connectum/ConnectumTests/ServiceBriefTests.swift`

- [ ] **Step 1: Write failing model-decode test**

```swift
import XCTest
@testable import Connectum

final class ServiceBriefTests: XCTestCase {
    func testBriefSectionsDecode() throws {
        let json = """
        {"sections":{"one_liner":"A CRM","icp":"founders","activation":"","signal_glossary":"","business_model":"","current_focus":""},"status":"ready","gaps":["activation"]}
        """.data(using: .utf8)!
        let brief = try JSONDecoder().decode(ServiceBrief.self, from: json)
        XCTAssertEqual(brief.sections.one_liner, "A CRM")
        XCTAssertEqual(brief.status, "ready")
        XCTAssertEqual(brief.gaps, ["activation"])
    }
    func testInterviewStepDecode() throws {
        let q = try JSONDecoder().decode(InterviewStep.self, from: #"{"question":"Who?","options":["A","B"]}"#.data(using: .utf8)!)
        if case let .question(text, opts) = q { XCTAssertEqual(text, "Who?"); XCTAssertEqual(opts, ["A","B"]) }
        else { XCTFail("expected question") }
        let d = try JSONDecoder().decode(InterviewStep.self, from: #"{"done":true}"#.data(using: .utf8)!)
        if case .done = d {} else { XCTFail("expected done") }
    }
}
```

- [ ] **Step 2: Run, verify fail** — `ServiceBrief`/`InterviewStep` undefined.

- [ ] **Step 3: Implement models**

```swift
import Foundation

struct BriefSections: Codable, Equatable, Sendable {
    var one_liner: String = ""
    var icp: String = ""
    var activation: String = ""
    var signal_glossary: String = ""
    var business_model: String = ""
    var current_focus: String = ""

    static let displayOrder: [(key: String, label: String)] = [
        ("one_liner", "한 줄 소개"),
        ("icp", "타깃 고객 (ICP)"),
        ("activation", "핵심 활성화·성공 기준"),
        ("signal_glossary", "핵심 행동·상태 신호의 의미"),
        ("business_model", "비즈니스 모델"),
        ("current_focus", "현재 집중 목표"),
    ]
    func value(for key: String) -> String {
        switch key {
        case "one_liner": return one_liner
        case "icp": return icp
        case "activation": return activation
        case "signal_glossary": return signal_glossary
        case "business_model": return business_model
        case "current_focus": return current_focus
        default: return ""
        }
    }
}

struct ServiceBrief: Codable, Sendable {
    let sections: BriefSections
    let status: String
    let gaps: [String]?
    var isEmpty: Bool { status != "ready" }
}

enum InterviewStep: Decodable, Sendable {
    case question(String, [String])
    case done
    private enum Keys: String, CodingKey { case question, options, done }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if (try? c.decode(Bool.self, forKey: .done)) == true { self = .done; return }
        let q = (try? c.decode(String.self, forKey: .question)) ?? ""
        let opts = (try? c.decode([String].self, forKey: .options)) ?? []
        self = .question(q, opts)
    }
}
```

- [ ] **Step 4: Add repository methods** — protocol additions in `CrmDataProviding`:

```swift
    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief?
    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief
    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep
```

Struct implementations:

```swift
    func fetchServiceBrief(serviceId: String) async throws -> ServiceBrief? {
        struct Row: Decodable { let sections: BriefSections; let status: String }
        let rows: [Row] = try await client.from("service_brief")
            .select("sections,status").eq("service_id", value: serviceId).limit(1).execute().value
        guard let r = rows.first else { return nil }
        return ServiceBrief(sections: r.sections, status: r.status, gaps: nil)
    }
    func synthesizeBrief(serviceId: String, document: String?, transcript: [[String: String]]?, currentSections: BriefSections?, userPrompt: String?) async throws -> ServiceBrief {
        struct Body: Encodable {
            let service_id: String; let mode = "synthesize"
            let document: String?; let transcript: [[String: String]]?
            let current_sections: BriefSections?; let user_prompt: String?
        }
        do {
            return try await client.functions.invoke("service-brief", options: FunctionInvokeOptions(
                body: Body(service_id: serviceId, document: document, transcript: transcript,
                           current_sections: currentSections, user_prompt: userPrompt)))
        } catch { throw normalizeFunctionError(error) }
    }
    func interviewStep(serviceId: String, transcript: [[String: String]], targetSections: [String]?) async throws -> InterviewStep {
        struct Body: Encodable { let service_id: String; let mode = "interview_step"; let transcript: [[String: String]]; let target_sections: [String]? }
        do {
            return try await client.functions.invoke("service-brief", options: FunctionInvokeOptions(
                body: Body(service_id: serviceId, transcript: transcript, target_sections: targetSections)))
        } catch { throw normalizeFunctionError(error) }
    }
```

- [ ] **Step 5: Run tests** — `ServiceBriefTests` pass. (Run via Xcode scheme or `xcodebuild test`.)

- [ ] **Step 6: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefModels.swift apps/Connectum/Connectum/Data/CrmRepository.swift apps/Connectum/ConnectumTests/ServiceBriefTests.swift
git commit -m "feat(service-brief): swift models + repository methods (TDD)"
```

### Task 8: ViewModel — load + prompt-edit + autodraft

**Files:**
- Create: `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefViewModel.swift`

- [ ] **Step 1: Implement** (interview orchestration added in Phase 3; Phase 1 = load/autodraft/prompt-edit)

```swift
import Foundation
import Observation

@MainActor
@Observable
final class ServiceBriefViewModel {
    var sections = BriefSections()
    var status = "empty"
    var isBusy = false
    var errorText: String?
    var promptText = ""

    private let repo: CrmDataProviding
    let serviceId: String
    init(serviceId: String, repo: CrmDataProviding = CrmRepository()) { self.serviceId = serviceId; self.repo = repo }

    var isEmpty: Bool { status != "ready" }

    func load() async {
        if let b = try? await repo.fetchServiceBrief(serviceId: serviceId), let b {
            sections = b.sections; status = b.status
        }
    }
    // First-pass draft from signals only.
    func autodraft() async { await run { try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: nil, transcript: nil, currentSections: nil, userPrompt: nil) } }
    // Natural-language edit; Claude rewrites the brief.
    func applyPrompt() async {
        let p = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        promptText = ""
        await run { try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: nil, transcript: nil, currentSections: self.sections, userPrompt: p) }
    }
    func ingestDocument(_ text: String) async {
        await run { try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: text, transcript: nil, currentSections: nil, userPrompt: nil) }
    }

    private func run(_ op: @escaping () async throws -> ServiceBrief) async {
        guard !isBusy else { return }
        isBusy = true; errorText = nil
        defer { isBusy = false }
        do { let b = try await op(); sections = b.sections; status = b.status }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefViewModel.swift
git commit -m "feat(service-brief): view model (load, autodraft, prompt-edit)"
```

### Task 9: View + chat banner entry (P1 minimal UI)

**Files:**
- Create: `apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefView.swift`
- Modify: `apps/Connectum/Connectum/Features/AIChat/AIChatView.swift` (banner + sheet)

- [ ] **Step 1: Implement `ServiceBriefView`** — read-only sections + prompt box + autodraft button. (Document/interview buttons added in P2/P3.)

```swift
import SwiftUI

struct ServiceBriefView: View {
    @State var model: ServiceBriefViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("서비스 브리프").font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button("닫기") { dismiss() }
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isEmpty {
                        emptyState
                    } else {
                        ForEach(BriefSections.displayOrder, id: \.key) { item in
                            let v = model.sections.value(for: item.key)
                            if !v.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label).font(.subheadline).bold().foregroundStyle(.secondary)
                                    Text(v).textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if let e = model.errorText { Text(e).font(.callout).foregroundStyle(.red) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            promptBar
        }
        .frame(width: 520, height: 620)
        .task { await model.load() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이 서비스에 대해 알려주면 AI가 훨씬 똑똑해집니다.")
                .font(.callout).foregroundStyle(.secondary)
            Button { Task { await model.autodraft() } } label: {
                Label("연동 정보로 초안 만들기", systemImage: "sparkles")
            }.disabled(model.isBusy)
        }
    }

    private var promptBar: some View {
        HStack(spacing: 8) {
            TextField("브리프를 어떻게 바꿀까요? (예: ICP에 B2B SaaS 추가)", text: $model.promptText, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4)
                .onSubmit { Task { await model.applyPrompt() } }
            Button { Task { await model.applyPrompt() } } label: { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.plain).disabled(model.isBusy || model.promptText.trimmingCharacters(in: .whitespaces).isEmpty)
        }.padding()
    }
}
```

- [ ] **Step 2: Add banner to `AIChatView`** — when brief empty, show a subtle bar that opens `ServiceBriefView` in a sheet. Add `@State private var showBrief = false` and a `@State private var briefEmpty = true`; check via `repo.fetchServiceBrief`. Minimal wiring:

```swift
// near top of AIChatView body, above the messages list:
if briefEmpty {
    Button { showBrief = true } label: {
        Label("AI가 이 서비스를 더 잘 이해하게 하기", systemImage: "lightbulb")
            .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain).padding(8)
    .background(.yellow.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 8)
}
```

```swift
.sheet(isPresented: $showBrief) {
    if let sid = viewModel.serviceId { ServiceBriefView(model: ServiceBriefViewModel(serviceId: sid)) }
}
.task(id: viewModel.serviceId) {
    if let sid = viewModel.serviceId {
        briefEmpty = ((try? await CrmRepository().fetchServiceBrief(serviceId: sid)) ?? nil)?.isEmpty ?? true
    }
}
```

- [ ] **Step 3: Build the app**

Run: `xcodebuild -project apps/Connectum/Connectum.xcodeproj -scheme Connectum -destination 'platform=macOS' build` (or open in Xcode and build).
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefView.swift apps/Connectum/Connectum/Features/AIChat/AIChatView.swift
git commit -m "feat(service-brief): brief view + ai-chat entry banner (P1 UI)"
```

---

## Phase 2: Document attachment (paste + .md/.txt/.pdf) + gap-fill trigger

### Task 10: `DocumentTextExtractor` (TDD)

**Files:**
- Create: `apps/Connectum/Connectum/Features/ServiceBrief/DocumentTextExtractor.swift`
- Test: extend `apps/Connectum/ConnectumTests/ServiceBriefTests.swift`

- [ ] **Step 1: Failing test**

```swift
func testExtractPlainText() throws {
    let data = "hello world".data(using: .utf8)!
    let text = try DocumentTextExtractor.extract(data: data, ext: "txt")
    XCTAssertEqual(text, "hello world")
}
func testEmptyExtractionThrows() {
    XCTAssertThrowsError(try DocumentTextExtractor.extract(data: Data(), ext: "txt"))
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation
import PDFKit

enum DocumentExtractError: LocalizedError {
    case empty, unsupported(String)
    var errorDescription: String? {
        switch self {
        case .empty: return "문서에서 텍스트를 찾지 못했습니다 (스캔 PDF일 수 있어요). 붙여넣기나 인터뷰를 이용하세요."
        case .unsupported(let e): return "지원하지 않는 형식입니다: .\(e)"
        }
    }
}

enum DocumentTextExtractor {
    static func extract(data: Data, ext: String) throws -> String {
        let text: String
        switch ext.lowercased() {
        case "txt", "md", "markdown", "text":
            text = String(data: data, encoding: .utf8) ?? ""
        case "pdf":
            guard let doc = PDFDocument(data: data) else { throw DocumentExtractError.empty }
            text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        default:
            throw DocumentExtractError.unsupported(ext)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw DocumentExtractError.empty }
        return trimmed
    }
}
```

- [ ] **Step 3: Run tests** — pass.

- [ ] **Step 4: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/DocumentTextExtractor.swift apps/Connectum/ConnectumTests/ServiceBriefTests.swift
git commit -m "feat(service-brief): document text extractor (txt/md/pdf, TDD)"
```

### Task 11: Document UI + gap-fill orchestration in VM

**Files:**
- Modify: `ServiceBriefViewModel.swift` (gaps + post-extract interview trigger flag)
- Modify: `ServiceBriefView.swift` (paste sheet + `.fileImporter`)

- [ ] **Step 1: VM — track gaps + paste/file ingest.** Add to VM:

```swift
    var pendingGaps: [String] = []   // sections still thin after extract → offer interview (Phase 3 wires the interview)
    var showPasteSheet = false
    var pasteText = ""

    func ingestPaste() async {
        let t = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        pasteText = ""; showPasteSheet = false
        await runCapturingGaps { try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: t, transcript: nil, currentSections: nil, userPrompt: nil) }
    }
    func ingestFile(url: URL) async {
        do {
            let needs = url.startAccessingSecurityScopedResource(); defer { if needs { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let text = try DocumentTextExtractor.extract(data: data, ext: url.pathExtension)
            await runCapturingGaps { try await self.repo.synthesizeBrief(serviceId: self.serviceId, document: text, transcript: nil, currentSections: nil, userPrompt: nil) }
        } catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
    private func runCapturingGaps(_ op: @escaping () async throws -> ServiceBrief) async {
        guard !isBusy else { return }
        isBusy = true; errorText = nil; defer { isBusy = false }
        do { let b = try await op(); sections = b.sections; status = b.status; pendingGaps = b.gaps ?? [] }
        catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
```

- [ ] **Step 2: View — add "문서로 채우기" menu (paste / file) and a gap banner.** Add to the prompt bar area / empty state a menu:

```swift
Menu {
    Button("텍스트 붙여넣기") { model.showPasteSheet = true }
    Button("파일 선택 (.md/.txt/.pdf)") { showImporter = true }
} label: { Label("문서로 채우기", systemImage: "doc.text") }
.disabled(model.isBusy)
```

Add `@State private var showImporter = false` and modifiers:

```swift
.fileImporter(isPresented: $showImporter, allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText], allowsMultipleSelection: false) { result in
    if case let .success(urls) = result, let url = urls.first { Task { await model.ingestFile(url: url) } }
}
.sheet(isPresented: $model.showPasteSheet) {
    VStack(spacing: 12) {
        Text("서비스 설명 문서 붙여넣기").font(.headline)
        TextEditor(text: $model.pasteText).frame(width: 460, height: 320).border(.quaternary)
        HStack { Button("취소") { model.showPasteSheet = false }; Spacer(); Button("분석") { Task { await model.ingestPaste() } }.keyboardShortcut(.return) }
    }.padding().frame(width: 500)
}
```

Add `import UniformTypeIdentifiers` at top of the view file.

- [ ] **Step 3: Build app** — `xcodebuild ... build` succeeds.

- [ ] **Step 4: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefView.swift apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefViewModel.swift
git commit -m "feat(service-brief): document attach (paste + file) with gap capture"
```

---

## Phase 3: Guided interview + gap auto-fill

### Task 12: Interview orchestration in VM

**Files:**
- Modify: `ServiceBriefViewModel.swift`

- [ ] **Step 1: Add interview state machine.**

```swift
    // Interview
    struct InterviewTurn: Identifiable { let id = UUID(); let role: String; let text: String }
    var interviewTurns: [InterviewTurn] = []
    var interviewOptions: [String] = []
    var interviewActive = false
    var interviewTargets: [String]? = nil   // gap-targeted when set
    var interviewAnswer = ""

    func startInterview(targets: [String]? = nil) async {
        interviewActive = true; interviewTargets = targets; interviewTurns = []; interviewOptions = []
        await nextInterviewStep()
    }
    func answerInterview(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        interviewAnswer = ""; interviewOptions = []
        interviewTurns.append(.init(role: "user", text: t))
        await nextInterviewStep()
    }
    private func transcriptWire() -> [[String: String]] { interviewTurns.map { ["role": $0.role, "content": $0.text] } }

    private func nextInterviewStep() async {
        guard !isBusy else { return }
        isBusy = true; errorText = nil; defer { isBusy = false }
        do {
            let step = try await repo.interviewStep(serviceId: serviceId, transcript: transcriptWire(), targetSections: interviewTargets)
            switch step {
            case .question(let q, let opts):
                interviewTurns.append(.init(role: "assistant", text: q)); interviewOptions = opts
            case .done:
                interviewActive = false
                let b = try await repo.synthesizeBrief(serviceId: serviceId, document: nil, transcript: transcriptWire(), currentSections: sections, userPrompt: nil)
                sections = b.sections; status = b.status; pendingGaps = b.gaps ?? []
            }
        } catch { errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription; interviewActive = false }
    }
```

- [ ] **Step 2: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefViewModel.swift
git commit -m "feat(service-brief): interview state machine + synthesize-on-done"
```

### Task 13: Interview UI + gap-fill button

**Files:**
- Modify: `ServiceBriefView.swift`

- [ ] **Step 1: Add interview overlay** — turn list, option buttons, answer field; "질문으로 채우기" entry; when `pendingGaps` non-empty after a doc/autodraft, show "부족한 부분 질문으로 채우기" that calls `startInterview(targets: pendingGaps)`.

```swift
// Entry (empty state / menu):
Button { Task { await model.startInterview() } } label: { Label("질문으로 채우기", systemImage: "bubble.left.and.text.bubble.right") }.disabled(model.isBusy)

// Gap nudge (shown when !pendingGaps.isEmpty && !interviewActive):
if !model.pendingGaps.isEmpty && !model.interviewActive {
    Button { Task { await model.startInterview(targets: model.pendingGaps) } } label: {
        Label("부족한 부분을 질문으로 채우기 (\(model.pendingGaps.count))", systemImage: "questionmark.bubble")
    }.disabled(model.isBusy)
}

// Interview overlay (when model.interviewActive):
if model.interviewActive {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(model.interviewTurns) { turn in
            Text(turn.text)
                .padding(8)
                .background(turn.role == "user" ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: turn.role == "user" ? .trailing : .leading)
        }
        if !model.interviewOptions.isEmpty {
            ForEach(model.interviewOptions, id: \.self) { opt in
                Button(opt) { Task { await model.answerInterview(opt) } }.disabled(model.isBusy)
            }
        }
        HStack {
            TextField("답변…", text: $model.interviewAnswer, axis: .vertical)
                .textFieldStyle(.roundedBorder).onSubmit { Task { await model.answerInterview(model.interviewAnswer) } }
            if model.isBusy { ProgressView().controlSize(.small) }
        }
    }
}
```

- [ ] **Step 2: Build app** — succeeds.

- [ ] **Step 3: Commit**

```bash
git add apps/Connectum/Connectum/Features/ServiceBrief/ServiceBriefView.swift
git commit -m "feat(service-brief): interview UI + gap-fill flow (P3)"
```

### Task 14: Post-create entry point

**Files:**
- Modify: `apps/Connectum/Connectum/Features/Connections/ServiceWizardView.swift` (after createService success)

- [ ] **Step 1:** On service-create success, present `ServiceBriefView` (or a card offering 문서/질문/나중에) for the new service id. Wire a `.sheet` keyed on the created service id; reuse `ServiceBriefView`. (Exact insertion point: where the wizard currently finishes / dismisses after `createService`.)

- [ ] **Step 2: Build app** — succeeds.

- [ ] **Step 3: Commit**

```bash
git add apps/Connectum/Connectum/Features/Connections/ServiceWizardView.swift
git commit -m "feat(service-brief): offer brief right after service creation"
```

---

## Self-Review notes
- Spec §5 modes (synthesize/interview_step) → Tasks 5, 12, 13. §5.3 injection → Task 6. §4 degrade → Task 3 `renderSignals`. §6 data model → Task 1. §7 flows → Tasks 8/11/12. §8 frontend → Tasks 7-14. §10 tests → Tasks 2,7,10.
- Status simplified from spec's `empty|draft|confirmed` to `empty|ready` (no explicit confirm step in a prompt-driven model). Spec §6/§2 updated to match.
- Type consistency: `BriefSections` keys identical across Deno (`BRIEF_SECTIONS`) and Swift (`BriefSections` struct). `synthesize` body fields (`current_sections`, `user_prompt`, `target_sections`) match handler parsing.
- `claudeComplete` throws `ai_reauth_required:*`; handler maps to 401 `{code:"ai_reauth_required"}`; Swift `normalizeFunctionError`/stream maps to reconnect (existing pattern).
```
