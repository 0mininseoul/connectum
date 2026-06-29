import { corsHeaders } from "../_shared/cors.ts";
import { isSupabaseReauthorizationError, tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { isMgmtHttpError, mgmtPost } from "../_shared/mgmt.ts";
import { LIST_TABLES_SQL, parseTables } from "./tables.ts";

function scopeMissingResponse(): Response {
  return new Response(JSON.stringify({
    code: "supabase_scope_missing",
    message: "Supabase 권한을 다시 승인해야 테이블 목록을 불러올 수 있습니다.",
    required_scope: "database:read",
  }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function reauthorizationResponse(): Response {
  return new Response(JSON.stringify({
    code: "supabase_reauthorization_required",
    message: "Supabase 권한을 다시 승인해야 테이블 목록을 불러올 수 있습니다.",
    required_scope: "database:read",
  }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id, project_ref } = await req.json();
    const token = await tokenForSupabaseAccount(account_id);
    const rows = await mgmtPost<Array<{ table_schema: string; table_name: string }>>(
      `/v1/projects/${project_ref}/database/query/read-only`, token, { query: LIST_TABLES_SQL });
    return new Response(JSON.stringify({ tables: parseTables(rows) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    if (isSupabaseReauthorizationError(e)) return reauthorizationResponse();
    if (isMgmtHttpError(e) && e.status === 403 && e.body.includes("scope")) {
      return scopeMissingResponse();
    }
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) Deno.serve(handle);
