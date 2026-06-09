import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getAccessToken } from "../_shared/gcp_token.ts";
import { generateSummary } from "../_shared/vertex.ts";

interface ConfirmBody {
  service_id?: string;
  title?: string;
  prompt?: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function buildPrompt(args: {
  service: Record<string, unknown>;
  tables: Record<string, unknown>[];
  title: string;
  userPrompt: string;
}): string {
  const tableContext = JSON.stringify(args.tables, null, 2);
  const serviceContext = JSON.stringify(args.service, null, 2);
  return [
    "당신은 Connectum의 KPI 설계 검토자입니다.",
    "사용자가 입력한 KPI 계산 프롬프트가 대시보드에 등록 가능한 정의인지 확인하세요.",
    "답변은 한국어로 짧고 명확하게 작성하세요.",
    "임의 SQL이나 파괴적 작업을 제안하지 말고, 읽기 전용 집계 로직만 허용하세요.",
    "",
    "[서비스 컨텍스트]",
    serviceContext,
    "",
    "[운영 DB 테이블/표시 컬럼 컨텍스트]",
    tableContext,
    "",
    `[KPI 이름] ${args.title}`,
    `[사용자 계산 프롬프트] ${args.userPrompt}`,
    "",
    "아래 네 섹션을 반드시 포함하세요.",
    "확인 요약: 대시보드에 표시될 KPI의 의미",
    "계산 정의: 어떤 데이터와 조건으로 값을 계산할지",
    "차트 계획: 날짜별 차트를 만들 때 어떤 날짜 컬럼과 집계 단위를 쓸지",
    "주의사항: 데이터가 부족하거나 모호한 점. 없으면 '없음'",
  ].join("\n");
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const body = await req.json() as ConfirmBody;
    const serviceId = clean(body.service_id);
    const title = clean(body.title);
    const userPrompt = clean(body.prompt);
    if (!serviceId || !title || !userPrompt) {
      return json({ error: "service_id, title, and prompt are required" }, 400);
    }

    const db = adminClient();
    const { data: service, error: serviceError } = await db.from("service")
      .select("id,name,supabase_project_ref,supabase_project_name,amplitude_project_name,axiom_dataset")
      .eq("id", serviceId)
      .single();
    if (serviceError) throw serviceError;

    const { data: tables, error: tableError } = await db.from("service_table")
      .select("source_schema,source_table,role,column_map,display_columns")
      .eq("service_id", serviceId);
    if (tableError) throw tableError;

    const token = await getAccessToken(Deno.env.get("GCP_SA_KEY_B64")!);
    const confirmationText = await generateSummary(
      token,
      Deno.env.get("GCP_PROJECT")!,
      Deno.env.get("GCP_LOCATION") ?? "global",
      Deno.env.get("GCP_MODEL") ?? "gemini-3.1-flash-lite",
      buildPrompt({ service, tables: tables ?? [], title, userPrompt }),
    );

    return json({
      title,
      summary: confirmationText,
      calculation_plan: confirmationText,
      chart_plan: confirmationText,
      warnings: [],
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
}

if (import.meta.main) Deno.serve(handle);
