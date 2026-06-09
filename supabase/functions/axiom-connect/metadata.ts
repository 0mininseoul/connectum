const API_BASE = "https://api.axiom.co/v2";

export type AxiomIdentity = {
  accountName: string | null;
  orgName: string | null;
  orgId: string | null;
};

function clean(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function bearerHeaders(token: string, orgId?: string | null): HeadersInit {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  if (orgId) headers["x-axiom-org-id"] = orgId;
  return headers;
}

export function parseCurrentUser(raw: unknown): string | null {
  if (!raw || typeof raw !== "object") return null;
  const user = raw as Record<string, unknown>;
  return clean(user.email) ?? clean(user.name);
}

export function parsePrimaryOrg(
  raw: unknown,
):
  | { id: string | null; name: string | null; primaryEmail: string | null }
  | null {
  if (!Array.isArray(raw)) return null;
  const first = raw.find((entry) => entry && typeof entry === "object") as
    | Record<string, unknown>
    | undefined;
  if (!first) return null;
  return {
    id: clean(first.id),
    name: clean(first.name),
    primaryEmail: clean(first.primaryEmail),
  };
}

async function fetchJson(
  path: string,
  token: string,
  orgId?: string | null,
): Promise<{ ok: boolean; status: number; json: unknown }> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: bearerHeaders(token, orgId),
  });
  if (!response.ok) {
    await response.body?.cancel();
    return { ok: false, status: response.status, json: null };
  }
  return { ok: true, status: response.status, json: await response.json() };
}

export async function fetchAxiomIdentity(
  token: string,
): Promise<AxiomIdentity> {
  let accountName: string | null = null;
  let orgName: string | null = null;
  let orgId: string | null = null;

  const user = await fetchJson("/user", token);
  if (user.ok) accountName = parseCurrentUser(user.json);

  const orgs = await fetchJson("/orgs", token);
  if (orgs.ok) {
    const org = parsePrimaryOrg(orgs.json);
    orgId = org?.id ?? null;
    orgName = org?.name ?? null;
    accountName = accountName ?? org?.primaryEmail ?? null;
  }

  return { accountName, orgName, orgId };
}

export async function fetchAxiomDatasets(
  token: string,
  orgId?: string | null,
): Promise<
  { ok: boolean; status: number; json: unknown; orgId: string | null }
> {
  const direct = await fetchJson("/datasets", token);
  if (direct.ok || !orgId) return { ...direct, orgId: null };

  const scoped = await fetchJson("/datasets", token, orgId);
  return { ...scoped, orgId };
}
