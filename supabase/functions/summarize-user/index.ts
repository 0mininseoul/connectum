import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getAccessToken } from "../_shared/gcp_token.ts";
import { buildSummaryPrompt, generateSummary } from "../_shared/vertex.ts";

async function sha256Hex(s: string): Promise<string> {
  const buf = new TextEncoder().encode(s).slice().buffer as ArrayBuffer;
  const d = await crypto.subtle.digest("SHA-256", buf);
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// Body: { crm_user_id, force? }. Builds the prompt, skips if the input hash is
// unchanged (cost control), else calls Gemini and stores the 3-line summary.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { crm_user_id, force } = await req.json();
    const db = adminClient();
    const { data: user, error } = await db.from("crm_user").select("*").eq("id", crm_user_id).single();
    if (error) throw error;
    const { data: events } = await db.from("crm_user_event")
      .select("event_type,event_time").eq("crm_user_id", crm_user_id).order("event_time", { ascending: false }).limit(30);
    const { data: blocks } = await db.from("page_block")
      .select("content").eq("crm_user_id", crm_user_id).eq("type", "channel_record");
    const records = (blocks ?? []).map((b) => b.content as Record<string, unknown>);
    const prompt = buildSummaryPrompt(user, events ?? [], records);
    const hash = await sha256Hex(prompt);
    if (!force && user.ai_summary_input_hash === hash && user.ai_summary) {
      return new Response(JSON.stringify({ skipped: true, ai_summary: user.ai_summary }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const token = await getAccessToken(Deno.env.get("GCP_SA_KEY_B64")!);
    const summary = await generateSummary(
      token, Deno.env.get("GCP_PROJECT")!, Deno.env.get("GCP_LOCATION") ?? "global",
      Deno.env.get("GCP_MODEL") ?? "gemini-3.1-flash-lite", prompt);
    await db.from("crm_user").update({
      ai_summary: summary, ai_summary_generated_at: new Date().toISOString(), ai_summary_input_hash: hash,
    }).eq("id", crm_user_id);
    return new Response(JSON.stringify({ ai_summary: summary }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
