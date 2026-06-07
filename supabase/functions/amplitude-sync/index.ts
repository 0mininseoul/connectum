import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { exportUrl, basicAuth } from "../_shared/amplitude.ts";
import { parseExportZip } from "../_shared/amplitude_export.ts";
import { mapExportRow, extractProfiles, type ExportRow } from "../sync/amplitude_map.ts";

function windowEnd(): Date {
  const d = new Date(Date.now() - 2 * 3600 * 1000);
  d.setUTCMinutes(0, 0, 0);
  return d;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const db = adminClient();
  const { service_id } = await req.json().catch(() => ({ service_id: undefined }));
  const { data: run } = await db.from("sync_run")
    .insert({ service_id, source: "amplitude", status: "running" }).select("id").single();
  try {
    const { data: svc, error: svcErr } = await db.from("service")
      .select("id, amplitude_account_id").eq("id", service_id).single();
    if (svcErr) throw svcErr;
    if (!svc.amplitude_account_id) throw new Error("service has no amplitude_account");
    const { data: acct } = await db.from("amplitude_account")
      .select("region, api_key_ref, secret_key_ref").eq("id", svc.amplitude_account_id).single();
    const apiKey = await getSecret(acct!.api_key_ref);
    const secret = await getSecret(acct!.secret_key_ref);

    const end = windowEnd();
    const { data: cur } = await db.from("sync_cursor")
      .select("cursor_value").eq("service_id", service_id).eq("source", "amplitude").eq("scope_key", "events").maybeSingle();
    const start = cur?.cursor_value ? new Date(cur.cursor_value) : new Date(end.getTime() - 24 * 3600 * 1000);
    if (start >= end) {
      await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats: { skipped: "no new window" } }).eq("id", run!.id);
      return new Response(JSON.stringify({ run_id: run!.id, events: 0, skipped: true }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const res = await fetch(exportUrl(acct!.region, start, end), { headers: { Authorization: basicAuth(apiKey, secret) } });
    let events = 0, profilesUpdated = 0;
    if (res.status === 200) {
      const bytes = new Uint8Array(await res.arrayBuffer());
      const rows = await parseExportZip(bytes) as unknown as ExportRow[];

      const matched = new Map<string, string>();
      const { data: users } = await db.from("crm_user").select("id, source_user_id").eq("service_id", service_id);
      for (const u of users ?? []) matched.set(u.source_user_id, u.id);

      const mapped = rows.map((r) => mapExportRow(r, matched)).filter((m): m is NonNullable<typeof m> => m !== null && m.event_uuid !== null);
      if (mapped.length) {
        const { error } = await db.from("crm_user_event").upsert(
          mapped.map((m) => ({ event_uuid: m.event_uuid, crm_user_id: m.crm_user_id, event_type: m.event_type, event_time: m.event_time, platform: m.platform, os: m.os, browser: m.browser, props: m.props })),
          { onConflict: "event_uuid" });
        if (error) throw error;
        events = mapped.length;
      }

      const profiles = extractProfiles(rows, matched);
      for (const [crmId, p] of profiles) {
        await db.from("crm_user").update({ amplitude_profile: p, updated_at: new Date().toISOString() }).eq("id", crmId);
        profilesUpdated++;
      }
    } else if (res.status !== 404) {
      await res.body?.cancel();
      throw new Error(`amplitude export -> ${res.status}`);
    } else {
      await res.body?.cancel();
    }

    await db.from("sync_cursor").upsert(
      { service_id, source: "amplitude", scope_key: "events", cursor_value: end.toISOString(), updated_at: new Date().toISOString() },
      { onConflict: "service_id,source,scope_key" });
    await db.from("sync_run").update({ status: "success", finished_at: new Date().toISOString(), stats: { events, profilesUpdated, window_end: end.toISOString() } }).eq("id", run!.id);
    return new Response(JSON.stringify({ run_id: run!.id, events, profilesUpdated }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (e) {
    await db.from("sync_run").update({ status: "error", finished_at: new Date().toISOString(), error: String(e) }).eq("id", run!.id);
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
