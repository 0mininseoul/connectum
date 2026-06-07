import { ZipReader, BlobReader, Uint8ArrayWriter, configure } from "jsr:@zip-js/zip-js@2";
import type { Entry } from "jsr:@zip-js/zip-js@2";

configure({ useWebWorkers: false });

type Row = Record<string, unknown>;

// deno-lint-ignore no-explicit-any
function toBlob(bytes: Uint8Array): Blob {
  return new Blob([bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as any]);
}

export async function gunzipNdjson(gz: Uint8Array): Promise<Row[]> {
  const text = await new Response(
    toBlob(gz).stream().pipeThrough(new DecompressionStream("gzip")),
  ).text();
  return text.split("\n").filter((l) => l.trim() !== "").map((l) => JSON.parse(l) as Row);
}

function hasGetData(entry: Entry): entry is Entry & {
  getData: (writer: Uint8ArrayWriter) => Promise<Uint8Array>;
} {
  return typeof (entry as { getData?: unknown }).getData === "function";
}

export async function parseExportZip(bytes: Uint8Array): Promise<Row[]> {
  const reader = new ZipReader(new BlobReader(toBlob(bytes)));
  const out: Row[] = [];
  for (const entry of await reader.getEntries()) {
    if (!entry.filename.endsWith(".gz") || !hasGetData(entry)) continue;
    const gz = await entry.getData(new Uint8ArrayWriter());
    out.push(...await gunzipNdjson(gz));
  }
  await reader.close();
  return out;
}
