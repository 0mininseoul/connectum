import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { parseDatasets } from "./datasets.ts";

// Body: { token, label }. Validates the Axiom token by listing datasets, stores
// the token in Vault, creates an axiom_account row, returns the dataset names.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { token, label } = await req.json();
    const res = await fetch("https://api.axiom.co/v1/datasets", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      return new Response(JSON.stringify({ error: `axiom validation failed: ${res.status}` }),
        { status: 400, headers: corsHeaders });
    }
    const datasets = parseDatasets(await res.json());

    const ref = `axiom_token_${crypto.randomUUID()}`;
    await setSecret(ref, token);
    const db = adminClient();
    const { data, error } = await db.from("axiom_account")
      .insert({ label: label ?? "Axiom", api_token_ref: ref }).select("id").single();
    if (error) throw error;

    return new Response(JSON.stringify({ account_id: data.id, datasets }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
