import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getAccessToken } from "../_shared/gcp_token.ts";
import { generateSummary } from "../_shared/vertex.ts";
import { computeKPI, KPISpec, validateSpec, valueText } from "../_shared/kpi_spec.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function clean(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function buildSpecPrompt(args: {
  service: Record<string, unknown>;
  tables: Record<string, unknown>[];
  title: string;
  prompt: string;
}): string {
  return [
    "당신은 Connectum의 KPI 계산 설계자입니다.",
    "사용자의 KPI 설명을 crm_user 테이블에 대한 구조화된 계산 스펙(JSON)으로 변환하세요.",
    "",
    "사용 가능한 필드(이외 사용 금지):",
    "- contact_status, email, display_name, created_at",
    "- profile.<컬럼>  (운영 DB 유저 테이블에서 동기화된 컬럼. 예: profile.auth_provider)",
    "- amplitude.<컬럼>",
    "",
    "[서비스] " + JSON.stringify(args.service),
    "[유저 테이블/컬럼] " + JSON.stringify(args.tables),
    "",
    `[KPI 이름] ${args.title}`,
    `[설명] ${args.prompt}`,
    "",
    "다음 JSON만 출력하세요(코드펜스/설명/머리말 금지):",
    '{"interpretation":"한 문장 해석","spec":{"kind":"count|ratio","filter":{"field":"...","op":"eq|neq|contains|not_null","value":"..."},"unit":"count|percent"}}',
    "비율(%)이면 kind=ratio·unit=percent, 개수면 kind=count·unit=count. 필터가 불필요하면 filter를 생략하세요.",
  ].join("\n");
}

function extractJSON(text: string): any {
  const match = text.match(/\{[\s\S]*\}/);
  if (!match) throw new Error("Gemini가 JSON을 반환하지 않았습니다: " + text.slice(0, 200));
  return JSON.parse(match[0]);
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  try {
    const body = await req.json();
    const serviceId = clean(body.service_id);
    if (!serviceId) return json({ error: "service_id required" }, 400);
    const db = adminClient();

    // Recompute path: a stored spec, no LLM call.
    if (body.spec) {
      const spec = validateSpec(body.spec);
      const c = await computeKPI(db, serviceId, spec);
      return json({ spec, ...c, unit: spec.unit, value_text: valueText(c.value, spec.unit) });
    }

    const title = clean(body.title);
    const prompt = clean(body.prompt);
    if (!prompt) return json({ error: "prompt required" }, 400);

    const { data: service } = await db.from("service")
      .select("name,supabase_project_name").eq("id", serviceId).single();
    const { data: tables } = await db.from("service_table")
      .select("role,column_map,display_columns").eq("service_id", serviceId);

    const token = await getAccessToken(Deno.env.get("GCP_SA_KEY_B64")!);
    const raw = await generateSummary(
      token,
      Deno.env.get("GCP_PROJECT")!,
      Deno.env.get("GCP_LOCATION") ?? "global",
      Deno.env.get("GCP_MODEL") ?? "gemini-3.1-flash-lite",
      buildSpecPrompt({ service: service ?? {}, tables: tables ?? [], title, prompt }),
    );

    let parsed: any;
    try {
      parsed = extractJSON(raw);
    } catch (e) {
      return json({ error: String(e) }, 422);
    }
    const spec: KPISpec = validateSpec(parsed.spec);
    const c = await computeKPI(db, serviceId, spec);
    return json({
      interpretation: clean(parsed.interpretation),
      spec,
      ...c,
      unit: spec.unit,
      value_text: valueText(c.value, spec.unit),
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
}

if (import.meta.main) Deno.serve(handle);
