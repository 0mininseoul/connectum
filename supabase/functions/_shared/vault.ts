import { adminClient } from "./admin.ts";

// Server-side secret access via the SECURITY DEFINER RPCs.
export async function getSecret(name: string): Promise<string> {
  const db = adminClient();
  const { data, error } = await db.rpc("vault_get", { secret_name: name });
  if (error) throw error;
  if (data == null) throw new Error(`secret not found: ${name}`);
  return data as string;
}

export async function setSecret(name: string, value: string): Promise<void> {
  const db = adminClient();
  const { error } = await db.rpc("vault_set", { secret_name: name, secret_value: value });
  if (error) throw error;
}
