// deno-lint-ignore-file no-explicit-any
import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { claudeComplete } from "../_shared/claude_chat.ts";
import { gatherSignals, renderSignals } from "./signals.ts";
import {
  BRIEF_SECTIONS,
  type BriefSections,
  buildInterviewPrompt,
  buildSynthesizePrompt,
  detectGaps,
  emptyBrief,
  parseInterviewJSON,
  parseSectionsJSON,
  type SectionKey,
} from "./brief.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function clean(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}
function errorResponse(e: unknown): Response {
  const msg = String(e);
  if (msg.includes("ai_reauth_required")) {
    return json({ code: "ai_reauth_required", message: msg }, 401);
  }
  return json({ error: msg }, 500);
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  let body: any;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad json" }, 400);
  }
  const serviceId = clean(body.service_id);
  const mode = clean(body.mode) || "synthesize";
  if (!serviceId) return json({ error: "service_id required" }, 400);
  const db = adminClient();

  try {
    const signals = renderSignals(await gatherSignals(db, serviceId));

    if (mode === "interview_step") {
      const transcript = Array.isArray(body.transcript) ? body.transcript : [];
      const targets = Array.isArray(body.target_sections)
        ? (body.target_sections.filter((s: unknown): s is SectionKey =>
          (BRIEF_SECTIONS as readonly string[]).includes(s as string)) as SectionKey[])
        : undefined;
      const raw = await claudeComplete(
        [buildInterviewPrompt({ signals, transcript, targetSections: targets })],
        "다음 단계를 진행하세요.",
        1024,
      );
      return json(parseInterviewJSON(raw));
    }

    // mode === "synthesize"
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
      service_id: serviceId,
      sections,
      status,
      updated_at: new Date().toISOString(),
    }, { onConflict: "service_id" });

    return json({ sections, status, gaps });
  } catch (e) {
    return errorResponse(e);
  }
}

if (import.meta.main) Deno.serve(handle);
