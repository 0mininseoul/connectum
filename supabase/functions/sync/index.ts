import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { planWindows } from "../_shared/chunk.ts";

// Phase 0 skeleton: opens a sync_run, plans chunked windows from the cursor,
// records the plan, and closes the run. Phase 1 fills each window with real
// Supabase/Amplitude/Axiom fetches + upserts. Callable by pg_cron and the app.
async function handleSync(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { data: run } = await db.from("sync_run")
    .insert({ source: "amplitude", status: "running" }).select("id").single();
  try {
    const since = new Date(Date.now() - 24 * 3600 * 1000); // Phase 1 reads sync_cursor instead
    const windows = planWindows(since, new Date(), 2);
    // Phase 1: for each window → fetch + map + upsert; advance sync_cursor.
    await db.from("sync_run").update({
      status: "success", finished_at: new Date().toISOString(),
      stats: { planned_windows: windows.length },
    }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, planned_windows: windows.length }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e) }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) {
  Deno.serve(handleSync);
}
