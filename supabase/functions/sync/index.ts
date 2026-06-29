import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { withInternalHeaders } from "../_shared/internal_auth.ts";

// Orchestrator: for each service, trigger the Supabase table sync and (when an
// Amplitude account is configured) the Amplitude event sync. Invoked by pg_cron
// (all services) or by the app ({ service_id } for one). Sub-syncs run as internal
// function calls so each keeps its own sync_run/cursor bookkeeping.
const FN_BASE = `${Deno.env.get("SUPABASE_URL")}/functions/v1`;
// Internal calls must present a valid JWT to the API gateway. The anon key is a
// project JWT; the service_role key is a non-JWT secret on newer projects (which
// the gateway rejects). The sub-functions do their own service-role DB work.
const FN_AUTH = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const REAUTHORIZE_CODE = "supabase_reauthorization_required";
const REAUTHORIZE_MESSAGE = "Supabase 연결이 만료됐습니다. Supabase 계정을 다시 연결하세요.";

type FunctionCallResult = { status: number; body: unknown };
type Failure = { source: string; code?: string; message: string };

async function callFn(name: string, body: unknown): Promise<FunctionCallResult> {
  const headers = withInternalHeaders({ "Content-Type": "application/json" });
  if (FN_AUTH.split(".").length === 3) headers.set("Authorization", `Bearer ${FN_AUTH}`);
  const res = await fetch(`${FN_BASE}/${name}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
  const text = await res.text();
  try { return { status: res.status, body: JSON.parse(text) }; } catch { return { status: res.status, body: text }; }
}

function bodyRecord(body: unknown): Record<string, unknown> | null {
  return body && typeof body === "object" && !Array.isArray(body) ? body as Record<string, unknown> : null;
}

function bodyMessage(body: unknown): string {
  const record = bodyRecord(body);
  if (!record) return typeof body === "string" ? body : "";
  const message = record.message ?? record.error;
  return typeof message === "string" ? message : "";
}

function bodyCode(body: unknown): string | undefined {
  const code = bodyRecord(body)?.code;
  return typeof code === "string" ? code : undefined;
}

function isReauthorizationFailure(code: string | undefined, message: string): boolean {
  return code === REAUTHORIZE_CODE
    || message.includes("Supabase OAuth refresh failed")
    || message.includes("No such refresh token found");
}

function failureFor(source: string, result: FunctionCallResult): Failure | null {
  if (result.status < 400) return null;
  const code = bodyCode(result.body);
  const message = bodyMessage(result.body) || `${source} sync failed with HTTP ${result.status}`;
  return {
    source,
    code: isReauthorizationFailure(code, message) ? REAUTHORIZE_CODE : code,
    message: isReauthorizationFailure(code, message) ? REAUTHORIZE_MESSAGE : message,
  };
}

async function handleSync(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const body = await req.json().catch(() => ({}));
  const onlyService = (body as { service_id?: string })?.service_id;

  let query = db.from("service").select("id, name, amplitude_account_id");
  if (onlyService) query = query.eq("id", onlyService);
  const { data: services, error } = await query;
  if (error) return new Response(JSON.stringify({ error: String(error) }), { status: 500, headers: corsHeaders });

  const results: Record<string, unknown> = {};
  let failed = false;
  let requiresReauthorization = false;
  const failures: Failure[] = [];
  for (const s of services ?? []) {
    const r: Record<string, unknown> = {};
    r.supabase = await callFn("supabase-sync-tables", { service_id: s.id });
    const supabaseFailure = failureFor("Supabase", r.supabase as FunctionCallResult);
    if (supabaseFailure) {
      failed = true;
      failures.push(supabaseFailure);
      requiresReauthorization ||= supabaseFailure.code === REAUTHORIZE_CODE;
    }
    if (s.amplitude_account_id) r.amplitude = await callFn("amplitude-sync", { service_id: s.id });
    if (r.amplitude) {
      const amplitudeFailure = failureFor("Amplitude", r.amplitude as FunctionCallResult);
      if (amplitudeFailure) {
        failed = true;
        failures.push(amplitudeFailure);
      }
    }

    // Auto-generate AI summaries for matched users that still lack one (bounded
    // per run so a periodic cron fills them gradually; summarize-user hash-skips
    // unchanged inputs to control cost).
    const { data: pending } = await db.from("crm_user")
      .select("id")
      .eq("service_id", s.id)
      .neq("contact_status", "excluded")
      .is("ai_summary", null)
      .neq("amplitude_profile", "{}")
      .limit(5);
    let summarized = 0;
    for (const u of pending ?? []) {
      const res = await callFn("summarize-user", { crm_user_id: u.id });
      if (res.status === 200) summarized++;
    }
    r.summarized = summarized;

    results[(s.name as string) ?? s.id] = r;
  }
  return new Response(JSON.stringify({
    services: services?.length ?? 0,
    results,
    code: requiresReauthorization ? REAUTHORIZE_CODE : undefined,
    message: requiresReauthorization ? REAUTHORIZE_MESSAGE : undefined,
    error: failed ? failures.map((f) => `${f.source}: ${f.message}`).join("; ") || "One or more sync steps failed" : undefined,
  }), {
    status: failed ? 500 : 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

if (import.meta.main) {
  Deno.serve(handleSync);
}
