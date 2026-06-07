import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import { parseProjects } from "./projects.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.access_token_ref);
    const raw = await mgmtGet<Array<{ id: string; name: string; region: string }>>("/v1/projects", token);
    return new Response(JSON.stringify({ projects: parseProjects(raw) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
