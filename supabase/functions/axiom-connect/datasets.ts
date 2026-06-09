export function parseDatasets(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((dataset) => {
    if (!dataset || typeof dataset !== "object") return [];
    const name = (dataset as { name?: unknown }).name;
    return typeof name === "string" && name.trim() ? [name.trim()] : [];
  });
}
