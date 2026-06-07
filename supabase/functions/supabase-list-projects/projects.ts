export interface ProjectOut { ref: string; name: string; region: string; }

export function parseProjects(
  raw: Array<{ id: string; name: string; region: string } & Record<string, unknown>>,
): ProjectOut[] {
  return raw.map((p) => ({ ref: p.id, name: p.name, region: p.region }));
}
