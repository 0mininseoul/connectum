import { corsHeaders } from "../_shared/cors.ts";
import { connectumAppLoopbackUri } from "../_shared/oauth_env.ts";
import { loopbackUriFromState } from "../_shared/supabase_oauth_state.ts";

export { loopbackUriFromState };

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
