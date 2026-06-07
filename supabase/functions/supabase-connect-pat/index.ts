import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";

// Body: { pat, label }. Validates a Supabase Personal Access Token (lists projects),
// stores it in Vault, and creates a supabase_account row. A simple alternative to
// the OAuth flow for an internal tool where services live in your own org.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { pat, label } = await req.json();
    const res = await fetch("https://api.supabase.com/v1/projects", {
      headers: { Authorization: `Bearer ${pat}` },
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ error: `validation failed: ${res.status}` }), { status: 400, headers: corsHeaders });
    }
    await res.body?.cancel();
    const ref = `supabase_pat_${crypto.randomUUID()}`;
    await setSecret(ref, pat);
    const db = adminClient();
    const { data, error } = await db.from("supabase_account")
      .insert({ label: label ?? "Supabase (PAT)", access_token_ref: ref }).select("id").single();
    if (error) throw error;
    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
