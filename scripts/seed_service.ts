// Run: LOCAL_SERVICE_ROLE_KEY=... deno run -A scripts/seed_service.ts <account_id> <project_ref> <schema.table> <role> <user_id_col> [email_col] [cursor_col]
import { createClient } from "jsr:@supabase/supabase-js@2";

const [accountId, projectRef, schemaTable, role, idCol, emailCol, cursorCol] = Deno.args;
if (!accountId || !projectRef || !schemaTable || !role || !idCol) {
  throw new Error("usage: <account_id> <project_ref> <schema.table> <role:user_table|related> <user_id_col> [email_col] [cursor_col]");
}
const [schema, table] = schemaTable.split(".");
const url = Deno.env.get("LOCAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("LOCAL_SERVICE_ROLE_KEY");
if (!serviceKey) throw new Error("Set LOCAL_SERVICE_ROLE_KEY (from `supabase status`)");

const db = createClient(url, serviceKey, { auth: { persistSession: false } });
const { data: svc, error: svcErr } = await db.from("service").insert({
  name: `${projectRef} (dev)`, supabase_account_id: accountId, supabase_project_ref: projectRef,
}).select("id").single();
if (svcErr) throw svcErr;
const columnMap = role === "user_table"
  ? { user_id: idCol, ...(emailCol ? { email: emailCol } : {}) }
  : { pk: idCol };
const { error: stErr } = await db.from("service_table").insert({
  service_id: svc.id, source_schema: schema, source_table: table, role, column_map: columnMap, cursor_column: cursorCol ?? "created_at",
});
if (stErr) throw stErr;
console.log("service id:", svc.id);
