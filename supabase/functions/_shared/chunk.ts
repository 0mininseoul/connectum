export interface Window { start: Date; end: Date; }

// Split [start, end) into windows of `hours`, clamping the last to `end`.
// Used to keep each Edge Function invocation within its execution budget.
export function planWindows(start: Date, end: Date, hours: number): Window[] {
  const out: Window[] = [];
  const stepMs = hours * 3600 * 1000;
  let cur = start.getTime();
  const endMs = end.getTime();
  while (cur < endMs) {
    const next = Math.min(cur + stepMs, endMs);
    out.push({ start: new Date(cur), end: new Date(next) });
    cur = next;
  }
  return out;
}
