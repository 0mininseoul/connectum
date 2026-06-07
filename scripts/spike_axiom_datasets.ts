// Run: deno run -A --env-file=.env.local scripts/spike_axiom_datasets.ts
// Proves "connect account → auto-load datasets" works (spec §6.3).
// Accepts AXIOM_TOKEN (preferred) or AXIOM_API_TOKEN.
const token = Deno.env.get("AXIOM_TOKEN") ?? Deno.env.get("AXIOM_API_TOKEN");
if (!token) throw new Error("AXIOM_TOKEN missing in .env.local");

const res = await fetch("https://api.axiom.co/v1/datasets", {
  headers: { Authorization: `Bearer ${token}` },
});
console.log("HTTP", res.status);
if (!res.ok) { console.error(await res.text()); Deno.exit(1); }
const datasets = await res.json() as Array<{ name: string }>;
console.log(`datasets: ${datasets.length}`);
for (const d of datasets) console.log(` - ${d.name}`);
