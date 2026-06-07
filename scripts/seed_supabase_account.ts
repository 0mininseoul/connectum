// Run: deno run -A --env-file=.env.local scripts/seed_supabase_account.ts
import { createClient } from "jsr:@supabase/supabase-js@2";

const pat = Deno.env.get("SUPABASE_PAT");
if (!pat) throw new Error("SUPABASE_PAT missing in .env.local");

const url = Deno.env.get("LOCAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("LOCAL_SERVICE_ROLE_KEY");
if (!serviceKey) throw new Error("Set LOCAL_SERVICE_ROLE_KEY (from `supabase status`) before running");

const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const ref = `supabase_pat_${crypto.randomUUID()}`;
const { error: vErr } = await db.rpc("vault_set", { secret_name: ref, secret_value: pat });
if (vErr) throw vErr;
const { data, error } = await db.from("supabase_account")
  .insert({ label: "PAT (dev)", access_token_ref: ref }).select("id").single();
if (error) throw error;
console.log("supabase_account id:", data.id);
console.log("token ref:", ref);
