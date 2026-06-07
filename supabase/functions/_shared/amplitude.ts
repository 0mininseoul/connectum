export function amplitudeHost(region?: string): string {
  return (region ?? "us").toLowerCase() === "eu" ? "analytics.eu.amplitude.com" : "amplitude.com";
}

// Amplitude Export expects YYYYMMDDTHH (note the literal 'T' before the hour).
export function stampHour(d: Date): string {
  const p = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}T${p(d.getUTCHours())}`;
}

// A cheap 1-hour Export probe used to validate credentials. 200 or 404 = valid creds.
export function exportProbeUrl(region: string | undefined, now: Date = new Date()): string {
  const end = stampHour(now);
  const start = stampHour(new Date(now.getTime() - 3600 * 1000));
  return `https://${amplitudeHost(region)}/api/2/export?start=${start}&end=${end}`;
}

export function basicAuth(key: string, secret: string): string {
  return "Basic " + btoa(`${key}:${secret}`);
}

// General export window URL (start inclusive hour, end inclusive hour), YYYYMMDDTHH.
export function exportUrl(region: string | undefined, start: Date, end: Date): string {
  return `https://${amplitudeHost(region)}/api/2/export?start=${stampHour(start)}&end=${stampHour(end)}`;
}
