import { corsHeaders } from "../_shared/cors.ts";

export function handleHealth(): Response {
  return new Response(JSON.stringify({ status: "ok", ts: new Date().toISOString() }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

if (import.meta.main) {
  Deno.serve((req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
    return handleHealth();
  });
}
