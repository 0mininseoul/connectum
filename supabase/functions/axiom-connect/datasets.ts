export function parseDatasets(raw: Array<{ name: string } & Record<string, unknown>>): string[] {
  return raw.map((d) => d.name);
}
