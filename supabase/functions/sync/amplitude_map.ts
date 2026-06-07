export interface ExportRow {
  user_id?: string; event_type: string; event_time: string;
  os_name?: string; device_family?: string; platform?: string;
  event_properties?: Record<string, unknown>;
}
export interface MappedEvent {
  crm_user_id: string; event_type: string; event_time: string;
  platform: string | null; os: string | null; browser: string | null;
  props: Record<string, unknown>;
}

// matchedUsers: source_user_id -> crm_user.id. Spec: only registered/matched users.
export function mapExportRow(row: ExportRow, matchedUsers: Map<string, string>): MappedEvent | null {
  if (!row.user_id) return null;
  const crmId = matchedUsers.get(row.user_id);
  if (!crmId) return null;
  return {
    crm_user_id: crmId,
    event_type: row.event_type,
    event_time: row.event_time.replace(" ", "T") + "Z",
    platform: row.platform ?? null,
    os: row.os_name ?? null,
    browser: row.device_family ?? null,
    props: row.event_properties ?? {},
  };
}
