export interface ExportRow {
  uuid?: string; user_id?: string; event_type: string; event_time: string;
  os_name?: string; device_family?: string; device_type?: string; platform?: string;
  country?: string; region?: string; city?: string;
  event_properties?: Record<string, unknown>;
}
export interface MappedEvent {
  event_uuid: string | null; crm_user_id: string; event_type: string; event_time: string;
  platform: string | null; os: string | null; browser: string | null;
  props: Record<string, unknown>;
}

function toIso(t: string): string {
  return t.replace(" ", "T") + "Z";
}

// matchedUsers: source_user_id -> crm_user.id. Spec: only registered/matched users.
export function mapExportRow(row: ExportRow, matchedUsers: Map<string, string>): MappedEvent | null {
  if (!row.user_id) return null;
  const crmId = matchedUsers.get(row.user_id);
  if (!crmId) return null;
  return {
    event_uuid: row.uuid ?? null,
    crm_user_id: crmId,
    event_type: row.event_type,
    event_time: toIso(row.event_time),
    platform: row.platform ?? null,
    os: row.os_name ?? null,
    browser: row.device_family ?? null,
    props: row.event_properties ?? {},
  };
}

export interface Profile {
  os: string | null; platform: string | null; device_family: string | null; device_type: string | null;
  country: string | null; region: string | null; city: string | null; last_event_time: string | null;
}

// Only the fields extractProfiles needs — export rows always have these, but
// callers (and tests) may pass minimal objects that omit unrelated ExportRow fields.
export interface ProfileSourceRow {
  user_id?: string; event_time: string;
  os_name?: string; device_family?: string; device_type?: string; platform?: string;
  country?: string; region?: string; city?: string;
}

// Keeps the most recent (by event_time) device/geo snapshot per matched crm_user.
export function extractProfiles(rows: ProfileSourceRow[], matchedUsers: Map<string, string>): Map<string, Profile> {
  const latestTime = new Map<string, string>();
  const out = new Map<string, Profile>();
  for (const row of rows) {
    if (!row.user_id) continue;
    const crmId = matchedUsers.get(row.user_id);
    if (!crmId) continue;
    const iso = toIso(row.event_time);
    const prev = latestTime.get(crmId);
    if (prev != null && iso <= prev) continue;
    latestTime.set(crmId, iso);
    out.set(crmId, {
      os: row.os_name ?? null, platform: row.platform ?? null,
      device_family: row.device_family ?? null, device_type: row.device_type ?? null,
      country: row.country ?? null, region: row.region ?? null, city: row.city ?? null,
      last_event_time: iso,
    });
  }
  return out;
}
