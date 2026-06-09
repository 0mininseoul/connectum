import { assertEquals } from "jsr:@std/assert";
import { parseDatasets } from "./datasets.ts";

Deno.test("parseDatasets keeps dataset names", () => {
  const out = parseDatasets([{ name: "prod-logs", id: "x" }, {
    name: "audit",
    id: "y",
  }]);
  assertEquals(out, ["prod-logs", "audit"]);
});

Deno.test("parseDatasets ignores malformed entries", () => {
  const out = parseDatasets([{ name: " prod " }, { name: "" }, {
    id: "missing",
  }, null]);
  assertEquals(out, ["prod"]);
});
