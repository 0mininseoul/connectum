import { corsHeaders } from "../_shared/cors.ts";
import { tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import { parseProjects } from "./projects.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { account_id } = await req.json();
    const token = await tokenForSupabaseAccount(account_id);
    const raw = await mgmtGet<Array<{ id: string; name: string; region: string }>>("/v1/projects", token);
    return new Response(JSON.stringify({ projects: parseProjects(raw) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
