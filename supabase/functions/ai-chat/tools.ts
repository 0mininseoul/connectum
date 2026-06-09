// deno-lint-ignore-file no-explicit-any
// Read-only chat tools exposed to Claude. Every query is scoped to the caller's
// selected service_id so the model cannot reach data outside the data boundary.

export const TOOL_DEFS = [
  {
    name: "get_service_overview",
    description:
      "Use first / for big-picture questions. Returns the selected service's total user count, contact-status breakdown, signups in the last 7 days, and the display column schema.",
    input_schema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "search_users",
    description:
      "Call this when the user asks about specific people or filtered groups. Searches crm_user in the selected service by email/name substring and optional contact_status.",
    input_schema: {
      type: "object",
      properties: {
        query: { type: "string", description: "email or name substring" },
        contact_status: { type: "string", description: "new | contacted | excluded" },
        limit: { type: "integer", description: "max rows, <=50" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "get_user_detail",
    description:
      "Call this to get the full profile of one user: supabase_profile, amplitude_profile, ai_summary, and notes/channel records. Requires crm_user_id from search_users.",
    input_schema: {
      type: "object",
      properties: { crm_user_id: { type: "string" } },
      required: ["crm_user_id"],
      additionalProperties: false,
    },
  },
  {
    name: "get_user_events",
    description: "Call this to list a user's recent product events. Requires crm_user_id.",
    input_schema: {
      type: "object",
      properties: {
        crm_user_id: { type: "string" },
        limit: { type: "integer", description: "<=50" },
      },
      required: ["crm_user_id"],
      additionalProperties: false,
    },
  },
  {
    name: "get_metrics",
    description:
      "Call this for aggregate counts: total users, contacted, profiled, signups in the last 7 days.",
    input_schema: { type: "object", properties: {}, additionalProperties: false },
  },
];

function clampLimit(n: unknown, def = 20, max = 50): number {
  const v = typeof n === "number" ? n : def;
  return Math.max(1, Math.min(max, Math.trunc(v)));
}

export async function runTool(
  db: any,
  serviceId: string,
  name: string,
  input: any,
): Promise<string> {
  switch (name) {
    case "get_service_overview": {
      const { data: users } = await db.from("crm_user")
        .select("contact_status,created_at,amplitude_profile")
        .eq("service_id", serviceId)
        .neq("contact_status", "excluded")
        .limit(2000);
      const rows = (users ?? []) as any[];
      const weekAgo = Date.now() - 7 * 24 * 3600 * 1000;
      const byStatus: Record<string, number> = {};
      let recent = 0;
      for (const r of rows) {
        byStatus[r.contact_status] = (byStatus[r.contact_status] ?? 0) + 1;
        if (r.created_at && new Date(r.created_at).getTime() >= weekAgo) recent++;
      }
      const { data: st } = await db.from("service_table")
        .select("display_columns")
        .eq("service_id", serviceId)
        .eq("role", "user_table")
        .limit(1);
      const cols = (st?.[0]?.display_columns ?? []) as string[];
      return JSON.stringify({ total: rows.length, by_status: byStatus, recent_7d: recent, display_columns: cols });
    }
    case "search_users": {
      let q = db.from("crm_user")
        .select("id,email,display_name,contact_status,ai_summary")
        .eq("service_id", serviceId)
        .neq("contact_status", "excluded");
      if (input?.contact_status) q = q.eq("contact_status", input.contact_status);
      if (input?.query) q = q.or(`email.ilike.%${input.query}%,display_name.ilike.%${input.query}%`);
      const { data } = await q.order("created_at", { ascending: false }).limit(clampLimit(input?.limit));
      const rows = (data ?? []) as any[];
      return JSON.stringify(rows.map((r) => ({
        crm_user_id: r.id,
        email: r.email,
        name: r.display_name,
        contact_status: r.contact_status,
        summary: (r.ai_summary ?? "").slice(0, 160),
      })));
    }
    case "get_user_detail": {
      const { data } = await db.from("crm_user")
        .select("id,email,display_name,contact_status,supabase_profile,amplitude_profile,ai_summary")
        .eq("service_id", serviceId)
        .eq("id", input.crm_user_id)
        .limit(1);
      const u = (data ?? [])[0];
      if (!u) return JSON.stringify({ error: "user not found in this service" });
      const { data: blocks } = await db.from("page_block")
        .select("type,content")
        .eq("crm_user_id", input.crm_user_id);
      return JSON.stringify({ ...u, blocks: blocks ?? [] });
    }
    case "get_user_events": {
      const { data } = await db.from("crm_user_event")
        .select("event_type,event_time,os,browser,platform")
        .eq("crm_user_id", input.crm_user_id)
        .order("event_time", { ascending: false })
        .limit(clampLimit(input?.limit));
      return JSON.stringify(data ?? []);
    }
    case "get_metrics": {
      const base = () =>
        db.from("crm_user")
          .select("*", { count: "exact", head: true })
          .eq("service_id", serviceId)
          .neq("contact_status", "excluded");
      const total = (await base()).count ?? 0;
      const contacted = (await base().eq("contact_status", "contacted")).count ?? 0;
      const profiled = (await base().neq("amplitude_profile", "{}")).count ?? 0;
      const weekAgo = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();
      const recent = (await base().gte("created_at", weekAgo)).count ?? 0;
      return JSON.stringify({ total, contacted, profiled, recent_7d: recent });
    }
    default:
      return JSON.stringify({ error: `unknown tool ${name}` });
  }
}
