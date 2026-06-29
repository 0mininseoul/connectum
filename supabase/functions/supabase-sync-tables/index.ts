import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { isSupabaseReauthorizationError, tokenForSupabaseAccount } from "../_shared/supabase_token.ts";
import { mgmtPost } from "../_shared/mgmt.ts";
import { buildSelectSQL } from "../_shared/sql.ts";
import { requireInternalRequest } from "../_shared/internal_auth.ts";
import { filterExcludedCrmUsers, rowToCrmUser, rowToMirroredRow, maxCursor } from "./map.ts";

const PAGE = 500;
const REAUTHORIZE_MESSAGE = "Supabase 연결이 만료됐습니다. Supabase 계정을 다시 연결하세요.";

function reauthorizationBody() {
  return {
    code: "supabase_reauthorization_required",
    message: REAUTHORIZE_MESSAGE,
    required_scope: "database:read",
  };
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const unauthorized = requireInternalRequest(req);
  if (unauthorized) return unauthorized;
  const db = adminClient();
  const { service_id } = await req.json().catch(() => ({ service_id: undefined }));
  const { data: run } = await db.from("sync_run")
    .insert({ service_id, source: "supabase", status: "running" }).select("id").single();
  const stats: Record<string, number> = {};
  try {
    const { data: svc, error: svcErr } = await db.from("service")
      .select("id, supabase_account_id, supabase_project_ref").eq("id", service_id).single();
    if (svcErr) throw svcErr;
    if (!svc.supabase_account_id) {
      throw new Error("Supabase account is not connected for this service");
    }
    const token = await tokenForSupabaseAccount(svc.supabase_account_id);
    const { data: tables } = await db.from("service_table").select("*").eq("service_id", service_id);
    const { data: excludedUsers, error: excludedErr } = await db.from("crm_user")
      .select("source_user_id")
      .eq("service_id", service_id)
      .eq("contact_status", "excluded");
    if (excludedErr) throw excludedErr;
    const excludedSourceUserIds = new Set((excludedUsers ?? []).map((u) => String(u.source_user_id)));

    for (const t of tables ?? []) {
      const scopeKey = `table:${t.source_schema}.${t.source_table}`;
      const { data: cur } = await db.from("sync_cursor")
        .select("cursor_value").eq("service_id", service_id).eq("source", "supabase").eq("scope_key", scopeKey).maybeSingle();
      const sql = buildSelectSQL({
        schema: t.source_schema, table: t.source_table, cursorColumn: t.cursor_column ?? "updated_at",
        cursorValue: cur?.cursor_value ?? undefined, limit: PAGE,
      });
      const rows = await mgmtPost<Record<string, unknown>[]>(
        `/v1/projects/${svc.supabase_project_ref}/database/query/read-only`, token, { query: sql });

      if (t.role === "user_table") {
        const mapped = rows.map((r) => rowToCrmUser(r, t.column_map ?? {}, service_id));
        const ups = filterExcludedCrmUsers(mapped, excludedSourceUserIds);
        stats[`${scopeKey}:excluded`] = (stats[`${scopeKey}:excluded`] ?? 0) + (mapped.length - ups.length);
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
    const body = isSupabaseReauthorizationError(e)
      ? reauthorizationBody()
      : { error: String(e) };
    await db.from("sync_run").update({
      status: "error",
      finished_at: new Date().toISOString(),
      error: "message" in body ? body.message : body.error,
      stats,
    }).eq("id", run!.id);
    return new Response(JSON.stringify(body), {
      status: isSupabaseReauthorizationError(e) ? 401 : 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}

if (import.meta.main) Deno.serve(handle);
