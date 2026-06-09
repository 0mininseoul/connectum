import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { parseDatasets } from "./datasets.ts";
import { fetchAxiomDatasets, fetchAxiomIdentity } from "./metadata.ts";

// Body: { token }. Validates the Axiom token by listing datasets, stores
// the token in Vault, creates an axiom_account row, returns provider metadata.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { token } = await req.json();
    if (typeof token !== "string" || !token.trim()) {
      return new Response(
        JSON.stringify({ error: "Axiom API token is required" }),
        { status: 400, headers: corsHeaders },
      );
    }
    const cleanToken = token.trim();
    const identity = await fetchAxiomIdentity(cleanToken);
    const datasetResponse = await fetchAxiomDatasets(
      cleanToken,
      identity.orgId,
    );
    if (!datasetResponse.ok) {
      return new Response(
        JSON.stringify({
          error: `axiom validation failed: ${datasetResponse.status}`,
        }),
        { status: 400, headers: corsHeaders },
      );
    }
    const datasets = parseDatasets(datasetResponse.json);

    const ref = `axiom_token_${crypto.randomUUID()}`;
    await setSecret(ref, cleanToken);
    const db = adminClient();
    const { data, error } = await db.from("axiom_account")
      .insert({
        label: identity.orgName ?? identity.accountName ?? "Axiom",
        account_name: identity.accountName,
        datasets,
        api_token_ref: ref,
      }).select("id").single();
    if (error) throw error;

    return new Response(
      JSON.stringify({
        account_id: data.id,
        datasets,
        account_name: identity.accountName,
        org_name: identity.orgName,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
}

if (import.meta.main) Deno.serve(handle);
