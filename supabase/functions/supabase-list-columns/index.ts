import { corsHeaders } from "../_shared/cors.ts";
import { isSupabaseReauthorizationError, tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { isMgmtHttpError, mgmtPost } from "../_shared/mgmt.ts";

function scopeMissingResponse(): Response {
  return new Response(JSON.stringify({
    code: "supabase_scope_missing",
    message: "Supabase 권한을 다시 승인해야 컬럼 정보를 불러올 수 있습니다.",
    required_scope: "database:read",
  }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function reauthorizationResponse(): Response {
  return new Response(JSON.stringify({
    code: "supabase_reauthorization_required",
    message: "Supabase 권한을 다시 승인해야 컬럼 정보를 불러올 수 있습니다.",
    required_scope: "database:read",
  }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Body: { account_id, project_ref, schema, table }. Lists a table's columns so the
// service wizard can let the user choose which to show in the operational DB table.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id, project_ref, schema, table } = await req.json();
    const token = await tokenForSupabaseAccount(account_id);
    const esc = (s: string) => String(s).replace(/'/g, "''");
    const sql =
      `select column_name, data_type from information_schema.columns ` +
      `where table_schema = '${esc(schema)}' and table_name = '${esc(table)}' order by ordinal_position`;
    const rows = await mgmtPost<Array<{ column_name: string; data_type: string }>>(
      `/v1/projects/${project_ref}/database/query/read-only`, token, { query: sql });
    const columns = rows.map((r) => ({ column: r.column_name, type: r.data_type }));
    return new Response(JSON.stringify({ columns }), {
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
