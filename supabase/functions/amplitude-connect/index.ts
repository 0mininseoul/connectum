import { corsHeaders } from "../_shared/cors.ts";
import { adminClient } from "../_shared/admin.ts";
import { setSecret } from "../_shared/vault.ts";
import { exportProbeUrl, basicAuth } from "../_shared/amplitude.ts";

// Body: { api_key, secret_key, region, label }. Validates via a 1-hour Export probe
// (200 or 404 = valid), stores both secrets in Vault, creates an amplitude_account row.
async function handle(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const { api_key, secret_key, region, label } = await req.json();
    const res = await fetch(exportProbeUrl(region), { headers: { Authorization: basicAuth(api_key, secret_key) } });
    await res.body?.cancel();
    if (res.status !== 200 && res.status !== 404) {
      return new Response(JSON.stringify({ error: `amplitude validation failed: ${res.status}` }),
        { status: 400, headers: corsHeaders });
    }
    const keyRef = `amplitude_key_${crypto.randomUUID()}`;
    const secretRef = `amplitude_secret_${crypto.randomUUID()}`;
    await setSecret(keyRef, api_key);
    await setSecret(secretRef, secret_key);
    const db = adminClient();
    const { data, error } = await db.from("amplitude_account").insert({
      label: label ?? "Amplitude", region: (region ?? "us").toLowerCase(),
      api_key_ref: keyRef, secret_key_ref: secretRef,
    }).select("id").single();
    if (error) throw error;
    return new Response(JSON.stringify({ account_id: data.id }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: corsHeaders });
  }
}

if (import.meta.main) Deno.serve(handle);
