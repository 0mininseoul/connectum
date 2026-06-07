const BASE = "https://api.supabase.com";

export function mgmtUrl(path: string): string {
  return `${BASE}/${path.replace(/^\//, "")}`;
}

export function mgmtHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

export async function mgmtGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(mgmtUrl(path), { headers: mgmtHeaders(token) });
  if (!res.ok) throw new Error(`mgmt GET ${path} -> ${res.status}: ${await res.text()}`);
  return await res.json() as T;
}

export async function mgmtPost<T>(path: string, token: string, body: unknown): Promise<T> {
  const res = await fetch(mgmtUrl(path), { method: "POST", headers: mgmtHeaders(token), body: JSON.stringify(body) });
  if (!res.ok) throw new Error(`mgmt POST ${path} -> ${res.status}: ${await res.text()}`);
  return await res.json() as T;
}
