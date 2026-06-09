import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { mgmtGet } from "../_shared/mgmt.ts";

// Body: { pat, label }. Validates a Supabase Personal Access Token (lists projects),
// stores it in Vault, and creates a supabase_account row. A simple alternative to
// the OAuth flow for an internal tool where services live in your own org.
type SupabaseProfile = {
  primary_email?: string | null;
  email?: string | null;
  username?: string | null;
  name?: string | null;
};

function displayNameFromProfile(profile: SupabaseProfile): string | null {
  return profile.primary_email ?? profile.email ?? profile.username ?? profile.name ?? null;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { pat, label } = await req.json();
    await mgmtGet("/v1/projects", pat);
    const profile = await mgmtGet<SupabaseProfile>("/v1/profile", pat).catch(() => null);
    const accountName = profile ? displayNameFromProfile(profile) : null;
    const ref = `supabase_pat_${crypto.randomUUID()}`;
    await setSecret(ref, pat);
    const db = adminClient();
    const safeLabel = label ?? accountName ?? "Supabase";
    const { data, error } = await db.from("supabase_account")
      .insert({ label: safeLabel, account_name: accountName, access_token_ref: ref }).select("id").single();
    if (error) throw error;
    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
