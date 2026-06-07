// Run: deno run -A --env-file=.env.local scripts/spike_supabase_mgmt.ts
// Proves a Personal Access Token can list projects (the data behind the
// "connect account → pick project" UX). OAuth replaces the PAT in Phase 1.
const pat = Deno.env.get("SUPABASE_PAT");
if (!pat) throw new Error("SUPABASE_PAT missing in .env.local");

const res = await fetch("https://api.supabase.com/v1/projects", {
  headers: { Authorization: `Bearer ${pat}` },
});
console.log("HTTP", res.status);
if (!res.ok) {
  console.error(await res.text());
  Deno.exit(1);
}
const projects = await res.json() as Array<{ id: string; name: string; region: string }>;
console.log(`projects: ${projects.length}`);
for (const p of projects.slice(0, 10)) console.log(` - ${p.name} (${p.id}, ${p.region})`);
