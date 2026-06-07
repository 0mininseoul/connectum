// Run: deno run -A --env-file=.env.local scripts/spike_amplitude_export.ts
// Confirms the free plan can hit the raw Export API. Export returns a gzip
// stream of events for a time window (Basic auth: apiKey:secretKey).
const key = Deno.env.get("AMPLITUDE_API_KEY");
const secret = Deno.env.get("AMPLITUDE_SECRET_KEY");
// Robust region parse: tolerate inline comments / whitespace (e.g. "us   # us | eu").
const region = (Deno.env.get("AMPLITUDE_REGION") ?? "us").trim().split(/\s+/)[0].toLowerCase();
if (!key || !secret) throw new Error("AMPLITUDE_API_KEY/SECRET_KEY missing in .env.local");

const host = region === "eu" ? "analytics.eu.amplitude.com" : "amplitude.com";
console.log(`region=${region} host=${host}`);
// Last 2 hours, Amplitude format YYYYMMDDTHH
const fmt = (d: Date) =>
  `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, "0")}${String(d.getUTCDate()).padStart(2, "0")}T${String(d.getUTCHours()).padStart(2, "0")}`;
const end = new Date();
const start = new Date(end.getTime() - 2 * 3600 * 1000);
const url = `https://${host}/api/2/export?start=${fmt(start)}&end=${fmt(end)}`;
const auth = btoa(`${key}:${secret}`);

const res = await fetch(url, { headers: { Authorization: `Basic ${auth}` } });
console.log("HTTP", res.status, "content-type:", res.headers.get("content-type"));
// 200 = data, 404 = no data in window (still proves access works), others = problem
if (res.status === 200 || res.status === 404) {
  console.log("Export API reachable on this plan ✅");
  await res.body?.cancel();
} else {
  console.error("Unexpected:", await res.text());
  Deno.exit(1);
}
