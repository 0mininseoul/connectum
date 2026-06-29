const STATE_PREFIX = "connectum.";

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + (4 - normalized.length % 4) % 4, "=");
  return atob(padded);
}

export function loopbackUriFromState(state: string | null | undefined): string | null {
  if (!state?.startsWith(STATE_PREFIX)) return null;
  try {
    const payload = JSON.parse(base64UrlDecode(state.slice(STATE_PREFIX.length))) as {
      loopback?: unknown;
    };
    if (typeof payload.loopback !== "string") return null;
    const url = new URL(payload.loopback);
    const port = Number(url.port);
    const hostAllowed = url.hostname === "127.0.0.1" || url.hostname === "localhost";
    const portAllowed = Number.isInteger(port) && port >= 1024 && port <= 65535;
    if (url.protocol !== "http:" || !hostAllowed || url.pathname !== "/callback" || !portAllowed) {
      return null;
    }
    return url.toString();
  } catch {
    return null;
  }
}
