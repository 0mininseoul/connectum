import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { mgmtGet } from "../_shared/mgmt.ts";
import {
  displayNameFromSupabaseProfile,
  type SupabaseProfile,
} from "../_shared/supabase_profile.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { account_id } = await req.json();
    const db = adminClient();
    const token = await tokenForSupabaseAccount(account_id);
    const profile = await mgmtGet<SupabaseProfile>("/v1/profile", token);
    const accountName = displayNameFromSupabaseProfile(profile);
    if (accountName) {
      await db.from("supabase_account").update({ account_name: accountName })
        .eq("id", account_id);
    }
    return new Response(JSON.stringify({ account_name: accountName }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
}

if (import.meta.main) Deno.serve(handle);
