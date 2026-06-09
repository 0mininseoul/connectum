const BASE = "https://api.supabase.com";

export class MgmtHttpError extends Error {
  constructor(
    message: string,
    public readonly status: number,
    public readonly body: string,
  ) {
    super(message);
    this.name = "MgmtHttpError";
  }
}

export function isMgmtHttpError(error: unknown): error is MgmtHttpError {
  return error instanceof MgmtHttpError;
}

export function mgmtUrl(path: string): string {
  return `${BASE}/${path.replace(/^\//, "")}`;
}

export function mgmtHeaders(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
}

export async function mgmtGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(mgmtUrl(path), { headers: mgmtHeaders(token) });
  if (!res.ok) {
    const body = await res.text();
    throw new MgmtHttpError(`mgmt GET ${path} -> ${res.status}: ${body}`, res.status, body);
  }
  return await res.json() as T;
}

export async function mgmtPost<T>(path: string, token: string, body: unknown): Promise<T> {
  const res = await fetch(mgmtUrl(path), { method: "POST", headers: mgmtHeaders(token), body: JSON.stringify(body) });
  if (!res.ok) {
    const responseBody = await res.text();
    throw new MgmtHttpError(`mgmt POST ${path} -> ${res.status}: ${responseBody}`, res.status, responseBody);
  }
  return await res.json() as T;
}
