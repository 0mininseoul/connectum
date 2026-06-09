import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { basicAuth, exportProbeUrl } from "../_shared/amplitude.ts";

// Body: { api_key, secret_key, project_name, region }. Validates via a 1-hour Export probe
// (200 or 404 = valid), stores both secrets in Vault, creates an amplitude_account row.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  try {
    const { api_key, secret_key, project_name, region } = await req.json();
    if (
      typeof api_key !== "string" || !api_key.trim() ||
      typeof secret_key !== "string" || !secret_key.trim() ||
      typeof project_name !== "string" || !project_name.trim()
    ) {
      return new Response(
        JSON.stringify({
          error: "Amplitude project name, API Key, and Secret Key are required",
        }),
        { status: 400, headers: corsHeaders },
      );
    }
    const cleanApiKey = api_key.trim();
    const cleanSecretKey = secret_key.trim();
    const cleanProjectName = project_name.trim();
    const cleanRegion =
      typeof region === "string" && region.toLowerCase() === "eu" ? "eu" : "us";
    const res = await fetch(exportProbeUrl(cleanRegion), {
      headers: { Authorization: basicAuth(cleanApiKey, cleanSecretKey) },
    });
    await res.body?.cancel();
    if (res.status !== 200 && res.status !== 404) {
      return new Response(
        JSON.stringify({ error: `amplitude validation failed: ${res.status}` }),
        { status: 400, headers: corsHeaders },
      );
    }
    const keyRef = `amplitude_key_${crypto.randomUUID()}`;
    const secretRef = `amplitude_secret_${crypto.randomUUID()}`;
    await setSecret(keyRef, cleanApiKey);
    await setSecret(secretRef, cleanSecretKey);
    const db = adminClient();
    const { data, error } = await db.from("amplitude_account").insert({
      label: cleanProjectName,
      account_name: null,
      project_name: cleanProjectName,
      region: cleanRegion,
      api_key_ref: keyRef,
      secret_key_ref: secretRef,
    }).select("id").single();
    if (error) throw error;
    return new Response(JSON.stringify({ account_id: data.id }), {
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
