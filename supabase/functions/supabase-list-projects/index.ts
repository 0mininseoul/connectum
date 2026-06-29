import { corsHeaders } from "../_shared/cors.ts";
import { isSupabaseReauthorizationError, tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import { parseProjects } from "./projects.ts";

function reauthorizationResponse(): Response {
  return new Response(JSON.stringify({
    code: "supabase_reauthorization_required",
    message: "Supabase 권한을 다시 승인해야 프로젝트 목록을 불러올 수 있습니다.",
    required_scope: "database:read",
  }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

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
    if (isSupabaseReauthorizationError(e)) return reauthorizationResponse();
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) Deno.serve(handle);
