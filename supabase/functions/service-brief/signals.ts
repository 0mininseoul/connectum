// deno-lint-ignore-file no-explicit-any
export interface Signals {
  service_name: string;
  supabase_project_name: string | null;
  user_columns: string[];
  event_types: string[];
  connections: { supabase: boolean; amplitude: boolean; axiom: boolean };
}

export async function gatherSignals(db: any, serviceId: string): Promise<Signals> {
  const { data: svc } = await db.from("service")
    .select("name,supabase_project_name,supabase_account_id,amplitude_account_id,axiom_account_id")
    .eq("id", serviceId).maybeSingle();
  const { data: st } = await db.from("service_table")
    .select("column_map,display_columns,role").eq("service_id", serviceId).eq("role", "user_table").limit(1);
  const userTable = (st ?? [])[0] ?? {};
  const cols = new Set<string>();
  for (const k of Object.keys((userTable.column_map ?? {}) as Record<string, unknown>)) cols.add(k);
  for (const c of (userTable.display_columns ?? []) as string[]) cols.add(c);

  // Top event types (only if any events exist). Sample users, then count in JS.
  let eventTypes: string[] = [];
  const { data: sampleUsers } = await db.from("crm_user").select("id").eq("service_id", serviceId).limit(50);
  const ids = (sampleUsers ?? []).map((r: any) => r.id);
  if (ids.length) {
    const { data: evs } = await db.from("crm_user_event")
      .select("event_type").in("crm_user_id", ids).limit(500);
    const counts: Record<string, number> = {};
    for (const e of (evs ?? []) as any[]) counts[e.event_type] = (counts[e.event_type] ?? 0) + 1;
    eventTypes = Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, 20).map(([k]) => k);
  }

  return {
    service_name: svc?.name ?? "",
    supabase_project_name: svc?.supabase_project_name ?? null,
    user_columns: [...cols],
    event_types: eventTypes,
    connections: {
      supabase: !!svc?.supabase_account_id,
      amplitude: !!svc?.amplitude_account_id,
      axiom: !!svc?.axiom_account_id,
    },
  };
}

export function renderSignals(s: Signals): string {
  return [
    `서비스명: ${s.service_name || "(미지정)"}`,
    s.supabase_project_name ? `Supabase 프로젝트: ${s.supabase_project_name}` : null,
    `유저 테이블 컬럼: ${s.user_columns.length ? s.user_columns.join(", ") : "(알 수 없음)"}`,
    s.event_types.length
      ? `관측된 주요 이벤트: ${s.event_types.join(", ")}`
      : "이벤트 로그 없음(분석 연동 미설정 또는 데이터 없음) — signal_glossary는 컬럼/상태 기반으로만 작성",
    `연동: supabase=${s.connections.supabase}, amplitude=${s.connections.amplitude}, axiom=${s.connections.axiom}`,
  ].filter(Boolean).join("\n");
}
