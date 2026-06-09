import { corsHeaders } from "../_shared/cors.ts";
import { connectumAppLoopbackUri } from "../_shared/oauth_env.ts";

const STATE_PREFIX = "connectum.";

function base64UrlDecode(value: string): string {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + (4 - normalized.length % 4) % 4, "=");
  return atob(padded);
}

export function loopbackUriFromState(state: string | null): string | null {
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

export function loopbackRedirect(req: Request): URL {
  const incoming = new URL(req.url);
  const target = new URL(loopbackUriFromState(incoming.searchParams.get("state")) ?? connectumAppLoopbackUri());
  for (const key of ["code", "state", "error", "error_description"]) {
    const value = incoming.searchParams.get(key);
    if (value) target.searchParams.set(key, value);
  }
  return target;
}

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const target = loopbackRedirect(req);
  if (req.method === "GET") {
    return new Response(null, {
      status: 302,
      headers: {
        ...corsHeaders,
        "Cache-Control": "no-store",
        Location: target.toString(),
      },
    });
  }
  return new Response("Method not allowed", { status: 405, headers: corsHeaders });
}

if (import.meta.main) {
  Deno.serve(handle);
}
