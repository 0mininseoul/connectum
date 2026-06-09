import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { getSecret } from "../_shared/vault.ts";
import { parseDatasets } from "../axiom-connect/datasets.ts";
import {
  fetchAxiomDatasets,
  fetchAxiomIdentity,
} from "../axiom-connect/metadata.ts";

async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { account_id } = await req.json();
    const db = adminClient();
    const { data: acct, error } = await db.from("axiom_account")
      .select("api_token_ref").eq("id", account_id).single();
    if (error) throw error;
    const token = await getSecret(acct.api_token_ref);
    const identity = await fetchAxiomIdentity(token);
    const res = await fetchAxiomDatasets(token, identity.orgId);
    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: `axiom datasets failed: ${res.status}` }),
        { status: 400, headers: corsHeaders },
      );
    }
    const datasets = parseDatasets(res.json);
    await db.from("axiom_account").update({ datasets }).eq("id", account_id);
    return new Response(JSON.stringify({ datasets }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
}

if (import.meta.main) Deno.serve(handle);
