type Row = Record<string, unknown>;
export interface CrmUserUpsert { service_id: string; source_user_id: string; email: string | null; supabase_profile: Row; }
export function rowToCrmUser(row: Row, columnMap: Record<string, string>, serviceId: string): CrmUserUpsert {
  const idCol = columnMap.user_id ?? "id";
  const emailCol = columnMap.email;
  const email = emailCol != null && row[emailCol] != null ? String(row[emailCol]) : null;
  return { service_id: serviceId, source_user_id: String(row[idCol]), email, supabase_profile: row };
}
export interface MirroredUpsert { service_id: string; service_table_id: string; source_pk: string; data: Row; }
export function rowToMirroredRow(row: Row, columnMap: Record<string, string>, serviceTableId: string, serviceId: string): MirroredUpsert {
  const pkCol = columnMap.pk ?? "id";
  return { service_id: serviceId, service_table_id: serviceTableId, source_pk: String(row[pkCol]), data: row };
}
export function maxCursor(rows: Row[], cursorColumn: string): string | null {
  let max: string | null = null;
  for (const r of rows) {
    const v = r[cursorColumn];
    if (v == null) continue;
    const s = String(v);
    if (max == null || s > max) max = s;
  }
  return max;
}
