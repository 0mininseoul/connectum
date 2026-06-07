import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtPost } from "../_shared/mgmt.ts";
import { LIST_TABLES_SQL, parseTables } from "./tables.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id, project_ref } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.access_token_ref);
    const rows = await mgmtPost<Array<{ table_schema: string; table_name: string }>>(
      `/v1/projects/${project_ref}/database/query`, token, { query: LIST_TABLES_SQL });
    return new Response(JSON.stringify({ tables: parseTables(rows) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
