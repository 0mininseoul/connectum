import { corsHeaders } from "./cors.ts";

const INTERNAL_SECRET_HEADER = "x-connectum-internal-secret";

function unauthorized(): Response {
  return new Response(JSON.stringify({ error: "Unauthorized internal function call" }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function timingSafeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

export function internalSecret(): string {
  return Deno.env.get("CONNECTUM_INTERNAL_FUNCTION_SECRET") ?? "";
}

export function requireInternalRequest(req: Request): Response | null {
  const expected = internalSecret();
  if (!expected) return null;
  const received = req.headers.get(INTERNAL_SECRET_HEADER) ?? "";
  if (!received || !timingSafeEqual(received, expected)) return unauthorized();
  return null;
}

export function withInternalHeaders(headers: HeadersInit = {}): Headers {
  const out = new Headers(headers);
  const secret = internalSecret();
  if (secret) out.set(INTERNAL_SECRET_HEADER, secret);
  return out;
}
