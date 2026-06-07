import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { mgmtPost } from "../_shared/mgmt.ts";
import { buildSelectSQL } from "../_shared/sql.ts";
import { rowToCrmUser, rowToMirroredRow, maxCursor } from "./map.ts";

const PAGE = 500;

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { service_id } = await req.json().catch(() => ({ service_id: undefined }));
  const { data: run } = await db.from("sync_run")
    .insert({ service_id, source: "supabase", status: "running" }).select("id").single();
  const stats: Record<string, number> = {};
  try {
    const { data: svc, error: svcErr } = await db.from("service")
      .select("id, supabase_account_id, supabase_project_ref").eq("id", service_id).single();
    if (svcErr) throw svcErr;
    const { data: acct } = await db.from("supabase_account")
      .select("access_token_ref").eq("id", svc.supabase_account_id).single();
    const token = await getSecret(acct!.access_token_ref);
    const { data: tables } = await db.from("service_table").select("*").eq("service_id", service_id);

    for (const t of tables ?? []) {
      const scopeKey = `table:${t.source_schema}.${t.source_table}`;
      const { data: cur } = await db.from("sync_cursor")
        .select("cursor_value").eq("service_id", service_id).eq("source", "supabase").eq("scope_key", scopeKey).maybeSingle();
      const sql = buildSelectSQL({
        schema: t.source_schema, table: t.source_table, cursorColumn: t.cursor_column ?? "updated_at",
        cursorValue: cur?.cursor_value ?? undefined, limit: PAGE,
      });
      const rows = await mgmtPost<Record<string, unknown>[]>(
        `/v1/projects/${svc.supabase_project_ref}/database/query`, token, { query: sql });

      if (t.role === "user_table") {
        const ups = rows.map((r) => rowToCrmUser(r, t.column_map ?? {}, service_id));
        if (ups.length) {
          const { error } = await db.from("crm_user").upsert(ups, { onConflict: "service_id,source_user_id" });
          if (error) throw error;
        }
      } else {
        const ups = rows.map((r) => rowToMirroredRow(r, t.column_map ?? {}, t.id, service_id));
        if (ups.length) {
          const { error } = await db.from("mirrored_row").upsert(ups, { onConflict: "service_table_id,source_pk" });
          if (error) throw error;
        }
      }
      stats[scopeKey] = (stats[scopeKey] ?? 0) + rows.length;

      const newCursor = maxCursor(rows, t.cursor_column ?? "updated_at");
      if (newCursor != null) {
        await db.from("sync_cursor").upsert(
          { service_id, source: "supabase", scope_key: scopeKey, cursor_value: newCursor, updated_at: new Date().toISOString() },
          { onConflict: "service_id,source,scope_key" });
      }
    }

    await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, stats }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e), stats }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
