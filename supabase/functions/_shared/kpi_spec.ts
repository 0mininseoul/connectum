// deno-lint-ignore-file no-explicit-any
// Structured, safe KPI computation over crm_user. The LLM emits one of these
// specs (never raw SQL); fields are allowlist-mapped and values parameterized,
// so there is no injection surface.

export type KPIKind = "count" | "ratio";
export type KPIOp = "eq" | "neq" | "contains" | "not_null";

export interface KPIFilter {
  field: string;
  op: KPIOp;
  value?: string;
}

export interface KPISpec {
  kind: KPIKind;
  filter?: KPIFilter;
  unit: "count" | "percent";
}

// Map a logical field name to a crm_user PostgREST column expression.
// Only known columns + sanitized jsonb keys are allowed.
export function fieldExpr(field: string): string {
  const f = (field ?? "").trim();
  const direct: Record<string, string> = {
    contact_status: "contact_status",
    email: "email",
    display_name: "display_name",
    created_at: "created_at",
    source_user_id: "source_user_id",
  };
  if (direct[f]) return direct[f];
  const m = f.match(/^(profile|amplitude)\.([A-Za-z0-9_]+)$/);
  if (m) {
    const col = m[1] === "profile" ? "supabase_profile" : "amplitude_profile";
    return `${col}->>${m[2]}`;
  }
  throw new Error(`unsupported KPI field: ${field}`);
}

export function validateSpec(raw: any): KPISpec {
  if (!raw || (raw.kind !== "count" && raw.kind !== "ratio")) {
    throw new Error("invalid KPI spec: kind must be count or ratio");
  }
  const unit: "count" | "percent" = raw.unit === "percent"
    ? "percent"
    : (raw.kind === "ratio" ? "percent" : "count");
  let filter: KPIFilter | undefined;
  if (raw.filter && typeof raw.filter === "object" && raw.filter.field) {
    const op: KPIOp = ["eq", "neq", "contains", "not_null"].includes(raw.filter.op)
      ? raw.filter.op
      : "eq";
    fieldExpr(raw.filter.field); // throws if field not allowed
    filter = {
      field: raw.filter.field,
      op,
      value: raw.filter.value != null ? String(raw.filter.value) : undefined,
    };
  }
  return { kind: raw.kind, filter, unit };
}

function applyFilter(q: any, filter: KPIFilter): any {
  const expr = fieldExpr(filter.field);
  switch (filter.op) {
    case "eq":
      return q.eq(expr, filter.value ?? "");
    case "neq":
      return q.neq(expr, filter.value ?? "");
    case "contains":
      return q.ilike(expr, `%${filter.value ?? ""}%`);
    case "not_null":
      return q.not(expr, "is", null);
  }
}

export async function computeKPI(
  db: any,
  serviceId: string,
  spec: KPISpec,
): Promise<{ value: number; numerator: number; denominator: number }> {
  const base = () =>
    db.from("crm_user")
      .select("*", { count: "exact", head: true })
      .eq("service_id", serviceId)
      .neq("contact_status", "excluded");

  let nq = base();
  if (spec.filter) nq = applyFilter(nq, spec.filter);
  const numerator = (await nq).count ?? 0;

  if (spec.kind === "count") {
    return { value: numerator, numerator, denominator: numerator };
  }
  const denominator = (await base()).count ?? 0;
  const value = denominator === 0 ? 0 : (numerator / denominator) * 100;
  return { value, numerator, denominator };
}

export function valueText(value: number, unit: string): string {
  return unit === "percent" ? `${value.toFixed(1)}%` : `${Math.round(value)}`;
}
