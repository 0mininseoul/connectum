import { assertEquals } from "jsr:@std/assert";
import { gunzipNdjson } from "./amplitude_export.ts";

async function gzip(s: string): Promise<Uint8Array> {
  const stream = new Blob([s]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

Deno.test("gunzipNdjson decompresses and parses newline-delimited JSON", async () => {
  const gz = await gzip('{"a":1}\n{"a":2,"b":"x"}\n');
  const rows = await gunzipNdjson(gz);
  assertEquals(rows.length, 2);
  assertEquals(rows[0].a, 1);
  assertEquals(rows[1].b, "x");
});

Deno.test("gunzipNdjson ignores blank lines", async () => {
  const gz = await gzip('{"a":1}\n\n');
  assertEquals((await gunzipNdjson(gz)).length, 1);
});
