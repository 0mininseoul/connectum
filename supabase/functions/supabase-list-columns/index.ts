import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtPost } from "../_shared/mgmt.ts";

// Body: { account_id, project_ref, schema, table }. Lists a table's columns so the
// service wizard can let the user choose which to show in the operational DB table.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id, project_ref, schema, table } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.access_token_ref);
    const esc = (s: string) => String(s).replace(/'/g, "''");
    const sql =
      `select column_name, data_type from information_schema.columns ` +
      `where table_schema = '${esc(schema)}' and table_name = '${esc(table)}' order by ordinal_position`;
    const rows = await mgmtPost<Array<{ column_name: string; data_type: string }>>(
      `/v1/projects/${project_ref}/database/query`, token, { query: sql });
    const columns = rows.map((r) => ({ column: r.column_name, type: r.data_type }));
    return new Response(JSON.stringify({ columns }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
