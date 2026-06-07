import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Service-role client for trusted server-side work inside Edge Functions.
export function adminClient(): SupabaseClient {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  return createClient(url, serviceKey, { auth: { persistSession: false } });
}
